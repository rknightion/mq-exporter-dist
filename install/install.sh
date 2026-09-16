#!/usr/bin/env bash
# RHEL 8.10 / 9.x x86-64. Installs release bytes, never compiles or changes MQ.
set -euo pipefail
umask 077
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
# Explicitly precede the loader cache, even when inherited LD_LIBRARY_PATH is empty.
# Do not change LD_PRELOAD or system loader configuration / monitoring injection.
system_tool() { LD_LIBRARY_PATH=/usr/lib64:/lib64 "$@"; }
verify_archive() (
  local archive=$1 checksums=$2 version=$3 scratch asset expected actual
  [[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] || die 'invalid version'
  [[ -f $archive && -f $checksums ]] || die 'archive and checksum file required'
  asset=mq-exporter-dist-$version-linux-amd64.tar.gz
  expected=$(awk -v n="$asset" '$2==n {print $1}' "$checksums")
  [[ $expected =~ ^[a-fA-F0-9]{64}$ ]] || die 'checksum missing or duplicated'
  expected=$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')
  if command -v sha256sum >/dev/null; then actual=$(sha256sum "$archive"); else actual=$(shasum -a 256 "$archive"); fi
  [[ ${actual%% *} == "$expected" ]] || die 'archive checksum mismatch'
  scratch=$(mktemp -d "${TMPDIR:-/tmp}/mq-exporter-verify.XXXXXXXX")
  trap 'rm -rf -- "$scratch"' EXIT
  tar -tzf "$archive" > "$scratch/names"
  tar -tvzf "$archive" > "$scratch/types"
  [[ $(wc -l < "$scratch/names") -eq 9 ]] || die 'unexpected archive file count'
  [[ $(sort -u "$scratch/names" | wc -l) -eq 9 ]] || die 'duplicate archive entries'
  while IFS= read -r name; do
    case "$name" in mq_prometheus|mq-config-check|mq-dist|install.sh|diagnose.sh|LICENSE|THIRD-PARTY-NOTICES.txt|build-metadata.json|sbom.cdx.json) ;; *) die 'unexpected archive path';; esac
  done < "$scratch/names"
  while IFS= read -r entry; do [[ ${entry:0:1} == - ]] || die 'archive links and special files forbidden'; done < "$scratch/types"
)
if [[ ${1:-} == --verify-archive ]]; then
  (($#==4)) || die '--verify-archive ARCHIVE CHECKSUMS VERSION'
  verify_archive "$2" "$3" "$4"
  printf 'Archive integrity and layout: PASS (no executable run)\n'
  exit 0
fi
usage() {
  printf '%s\n' 'install.sh --version vX.Y.Z[-rc.N] --instance qm1 --qmgr QM1 --service-user mqmon' \
    '  [--archive FILE --checksums FILE] [--mq-path /opt/mqm] [--root /opt/mq-exporter]' \
    '  [--port 9157] [--queues APP.*,!SYSTEM.*,!AMQ.*] [--channels *]' \
    '  [--mode bindings|client --channel NAME --conn-name mq.example.com(1414)]' \
    '  [--ccdt URL] [--user MQUSER --password-file FILE]' \
    '  [--replace-config] [--repoint] [--no-start] [--list-qmgrs]'
}
version='' instance='' qmgr='' account='' archive='' checksums='' mq=/opt/mqm root=/opt/mq-exporter
port=9157 queues='APP.*,!SYSTEM.*,!AMQ.*' channels='*' mode=bindings channel='' conn='' ccdt='' user='' password=''
replace=0 repoint=0 start=1 list=0
while (($#)); do
  case "$1" in
    --help|-h) usage; exit 0;;
    --replace-config) replace=1; shift; continue;;
    --repoint) repoint=1; shift; continue;;
    --no-start) start=0; shift; continue;;
    --list-qmgrs) list=1; shift; continue;;
  esac
  (($# >= 2)) || die 'option requires a value'
  case "$1" in
    --version) version=$2;; --instance) instance=$2;; --qmgr) qmgr=$2;; --service-user) account=$2;;
    --archive) archive=$2;; --checksums) checksums=$2;; --mq-path) mq=$2;; --root) root=$2;;
    --port) port=$2;; --queues) queues=$2;; --channels) channels=$2;; --mode) mode=$2;;
    --channel) channel=$2;; --conn-name) conn=$2;; --ccdt) ccdt=$2;; --user) user=$2;; --password-file) password=$2;;
    *) die 'unknown option';;
  esac
  shift 2
done
if ((list)); then exec "$mq/bin/dspmq" -o installation; fi
[[ $version =~ ^v[0-9]+\.[0-9]+\.[0-9]+(-rc\.[0-9]+)?$ ]] || die 'explicit version required'
[[ $instance =~ ^[a-z][a-z0-9-]{0,39}$ ]] || die 'invalid instance'
[[ $account =~ ^[a-z_][a-z0-9_-]*$ ]] || die 'existing service account required'
[[ $qmgr =~ ^[A-Za-z0-9._/%]{1,48}$ ]] || die 'invalid queue manager'
if [[ ! $port =~ ^[1-9][0-9]{0,4}$ ]] || ((port>65535)); then die 'port must be 1..65535'; fi
[[ $(uname -s) == Linux && $(uname -m) == x86_64 ]] || die 'Linux x86-64 required'
glibc=$(system_tool getconf GNU_LIBC_VERSION)
[[ $glibc == 'glibc 2.28' || $glibc == 'glibc 2.34' ]] || die 'initial targets require glibc 2.28 or 2.34'
((EUID==0)) || die 'run installation as root'
id "$account" >/dev/null 2>&1 || die 'service account does not exist'
[[ $(id -u "$account") != 0 ]] || die 'service account must not be root'
for p in "$root" "$mq"; do
  [[ $p == /* && $p != / && $p != *..* && $p =~ ^[a-zA-Z0-9/\ ._()-]+$ ]] || die 'unsafe installation path'
  case "$p" in /home/*|/root/*|/tmp/*|/var/tmp/*) die 'path is hidden by service sandbox';; esac
  [[ $(realpath -m "$p") == "$p" ]] || die 'noncanonical or symlinked path'
  ancestor=$p
  while [[ $ancestor != / ]]; do
    if [[ -e $ancestor ]]; then
      [[ $(stat -c %u "$ancestor") == 0 ]] || die 'installation ancestors must be root-owned'
      perm=$(stat -c %a "$ancestor"); (( (8#$perm & 0022) == 0 )) || die 'installation ancestor is group/world writable'
    fi
    ancestor=$(dirname "$ancestor")
  done
done
[[ -r $mq/lib64/libmqm_r.so ]] || die 'existing 64-bit MQ runtime missing'
mqversion=$(env LD_LIBRARY_PATH="$mq/lib64:/usr/lib64:/lib64" "$mq/bin/dspmqver" -f 2) || die 'MQ runtime version unavailable'
[[ $(awk '$1=="Version:" {print $2}' <<< "$mqversion") == 9.3.0.27 ]] || die 'initial Linux runtime target is MQ 9.3.0.27'
command -v systemctl >/dev/null || die 'systemd required'
command -v runuser >/dev/null || die 'runuser required'
if [[ -n $password ]]; then
  case "$password" in /home/*|/root/*|/tmp/*|/var/tmp/*) die 'password path is hidden by service sandbox';; esac
  [[ -f $password && ! -L $password ]] || die 'password file missing or symlinked'
  perm=$(stat -c %a "$password"); (( (8#$perm & 0077) == 0 )) || die 'password file must be owner-only'
  runuser -u "$account" -- test -r "$password" || die 'service cannot read password file'
fi
dest=$root/$instance
unit=mq-exporter-$instance.service
[[ $(realpath -m "$dest") == "$dest" ]] || die 'symlinked instance directory'
if [[ -e $dest ]]; then
  [[ -d $dest && $(stat -c %u "$dest") == 0 ]] || die 'instance directory must be root-owned'
  perm=$(stat -c %a "$dest"); (( (8#$perm & 0022) == 0 )) || die 'instance directory must not be group/world writable'
fi
[[ ! -e /etc/systemd/system/$unit || -f $dest/identity ]] || die 'unit exists outside this installer'
if [[ -d $root ]]; then
  for p in "$root"/*/port; do
    [[ -f $p && $p != "$dest/port" ]] || continue
    [[ $(<"$p") != "$port" ]] || die 'port already reserved by another instance'
  done
fi
scratch=$(mktemp -d /var/tmp/mq-exporter-install.XXXXXXXX)
# Only the uniquely created directory belongs to this invocation.
trap 'rm -rf -- "$scratch"' EXIT
asset=mq-exporter-dist-$version-linux-amd64.tar.gz
if [[ -z $archive ]]; then
  [[ -z $checksums ]] || die 'checksums requires archive'
  base=https://github.com/rknightion/mq-exporter-dist/releases/download/$version
  system_tool curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 600 "$base/$asset" -o "$scratch/$asset"
  system_tool curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 120 "$base/SHA256SUMS" -o "$scratch/SHA256SUMS"
  archive=$scratch/$asset; checksums=$scratch/SHA256SUMS
fi
if [[ $archive != "$scratch/$asset" ]]; then
  cp -- "$archive" "$scratch/$asset"
  archive=$scratch/$asset
fi
verify_archive "$archive" "$checksums" "$version"
mkdir "$scratch/payload"
tar -xzf "$archive" --no-same-owner --no-same-permissions -C "$scratch/payload"
helper=$scratch/payload/mq-dist
chmod 755 "$helper" "$scratch/payload/mq_prometheus" "$scratch/payload/mq-config-check"
"$helper" inspect "$scratch/payload/mq_prometheus"
"$helper" metadata "$scratch/payload/build-metadata.json" "$version" linux-amd64
"$helper" config --qmgr "$qmgr" --port "$port" --queues "$queues" --channels "$channels" --mode "$mode" --channel "$channel" --conn-name "$conn" --ccdt "$ccdt" --user "$user" --password-file "$password" > "$scratch/config.json"
for value in "$qmgr" "$port" "$account" "$mq" "$mode" "$channel" "$conn" "$ccdt"; do
  [[ $value != *$'\n'* && $value != *$'\r'* ]] || die 'control character in identity'
  printf '%s\n' "$value"
done > "$scratch/identity"
if [[ -e $dest/identity ]] && ! cmp -s "$dest/identity" "$scratch/identity"; then
  ((repoint && replace)) || die 'instance identity differs; explicit --repoint --replace-config required'
fi
config=$scratch/config.json
if [[ -e $dest/config.json && $replace == 0 ]]; then config=$dest/config.json; fi
"$helper" same-identity "$scratch/config.json" "$config"
env LD_BIND_NOW=1 LD_LIBRARY_PATH="$mq/lib64:/usr/lib64:/lib64" timeout 20 "$scratch/payload/mq_prometheus" --help >/dev/null 2>&1 || die 'exporter load/smoke check failed'
# The reader must run as the intended service user, with no inherited MQ overrides.
chmod 755 "$scratch" "$scratch/payload"
chown "$account" "$scratch/config.json"; chmod 600 "$scratch/config.json"
runuser -u "$account" -- env -i PATH=/usr/bin:/bin LD_BIND_NOW=1 LD_LIBRARY_PATH="$mq/lib64:/usr/lib64:/lib64" timeout 20 "$scratch/payload/mq-config-check" -f "$config" || die 'upstream configuration validation failed'
mkdir -p "$dest"
chmod 755 "$root" "$dest"
exec 9>"$root/.install.lock"
flock -n 9 || die 'another installer is active'
# Recheck reservations after obtaining the install lock.
for p in "$root"/*/port; do
  [[ -f $p && $p != "$dest/port" ]] || continue
  [[ $(<"$p") != "$port" ]] || die 'port reserved by another instance'
done
if [[ -e $dest/identity ]] && ! cmp -s "$dest/identity" "$scratch/identity"; then
  ((repoint && replace)) || die 'instance changed during preflight'
fi
for name in mq_prometheus mq-config-check mq-dist; do "$helper" replace "$scratch/payload/$name" "$dest/$name"; done
if [[ ! -e $dest/config.json || $replace == 1 ]]; then
  "$helper" replace "$scratch/config.json" "$dest/config.json"
  chown "$account" "$dest/config.json"; chmod 600 "$dest/config.json"
fi
"$helper" replace "$scratch/identity" "$dest/identity"
printf '%s\n' "$port" > "$scratch/port"
"$helper" replace "$scratch/port" "$dest/port"
cat > "$scratch/$unit" <<EOF
[Unit]
Description=IBM MQ exporter instance $instance (community distribution)
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0

[Service]
Type=simple
User=$account
ExecStart="$dest/mq_prometheus" -f "$dest/config.json"
Environment="LD_LIBRARY_PATH=$mq/lib64:/usr/lib64:/lib64"
Restart=on-failure
RestartSec=15s
UMask=0077
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=-/var/mqm
ProtectHome=true
# MQ local bindings may require the host IPC namespace and shared /tmp.
PrivateTmp=false
# EL8 systemd uses the host IPC namespace by default.

[Install]
WantedBy=multi-user.target
EOF
chmod 644 "$scratch/$unit"
systemd-analyze verify "$scratch/$unit" || die 'unit validation failed'
"$helper" replace "$scratch/$unit" "/etc/systemd/system/$unit"
systemctl daemon-reload
systemctl enable "$unit"
if ((start)); then systemctl restart "$unit"; fi
printf 'Installed %s, instance %s. Connection and queue coverage are not yet verified.\n' "$version" "$instance"
printf 'Check: "%s/mq-dist" health --qmgr "%s" --url "http://127.0.0.1:%s/metrics"\n' "$dest" "$qmgr" "$port"
