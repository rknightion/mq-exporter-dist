#!/usr/bin/env bash
# RHEL 8.10 / 9.x x86-64. Updates installer-managed exporter instances serially,
# one verified release per track, with per-instance snapshots and rollback.
set -euo pipefail
umask 077
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
die() { printf 'ERROR: %s\n' "$*" >&2; exit 1; }
system_tool() { LD_LIBRARY_PATH=/usr/lib64:/lib64 "$@"; }
selinux_active() { [[ -e /sys/fs/selinux/enforce ]]; }
version_pattern='^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(-(custom-)?[1-9][0-9]*)?(-rc\.[1-9][0-9]*)?$'
version_track() { [[ $1 == *-custom-* ]] && printf custom || printf native; }
usage() {
  printf '%s\n' 'update.sh [--native-version vX.Y.Z-N] [--custom-version vX.Y.Z-custom-N]' \
    '  [--native-archive FILE --native-checksums FILE] [--otel-archive FILE --otel-checksums FILE]' \
    '  [--custom-archive FILE --custom-checksums FILE]' \
    '  [--root DIR]... [--instance NAME]... [--dry-run] [--verify health|active]' \
    '  [--health-timeout SECONDS] [--settle SECONDS] [--allow-downgrade] [--include-unhealthy]' \
    '  Each instance keeps its variant and follows its own track: native Prometheus and' \
    '  OTel instances follow --native-version, custom instances --custom-version.'
}
native_version='' custom_version=''
declare -A archive_arg=() checksums_arg=()
roots=(/opt/mq-exporter) only=() dry_run=0 verify=health health_timeout=120 settle=20
allow_downgrade=0 include_unhealthy=0
while (($#)); do
  case "$1" in
    --help|-h) usage; exit 0;;
    --dry-run) dry_run=1; shift; continue;;
    --allow-downgrade) allow_downgrade=1; shift; continue;;
    --include-unhealthy) include_unhealthy=1; shift; continue;;
  esac
  (($# >= 2)) || die 'option requires a value'
  case "$1" in
    --native-version) native_version=$2;; --custom-version) custom_version=$2;;
    --native-archive) archive_arg[prometheus]=$2;; --native-checksums) checksums_arg[prometheus]=$2;;
    --otel-archive) archive_arg[otel]=$2;; --otel-checksums) checksums_arg[otel]=$2;;
    --custom-archive) archive_arg[custom]=$2;; --custom-checksums) checksums_arg[custom]=$2;;
    --root) roots+=("$2");; --instance) only+=("$2");; --verify) verify=$2;;
    --health-timeout) health_timeout=$2;; --settle) settle=$2;;
    *) die 'unknown option';;
  esac
  shift 2
done
[[ -n $native_version || -n $custom_version ]] || die 'at least one of --native-version or --custom-version required'
if [[ -n $native_version ]]; then
  [[ $native_version =~ $version_pattern && $(version_track "$native_version") == native ]] || die 'invalid native version'
fi
if [[ -n $custom_version ]]; then
  [[ $custom_version =~ $version_pattern && $(version_track "$custom_version") == custom ]] || die 'invalid custom version; expected vX.Y.Z-custom-N'
fi
[[ $verify == health || $verify == active ]] || die 'verify must be health or active'
[[ $health_timeout =~ ^[1-9][0-9]{0,3}$ && $settle =~ ^[0-9]{1,4}$ ]] || die 'invalid timeout'
for kind in prometheus otel custom; do
  if { [[ -n ${archive_arg[$kind]:-} ]] && [[ -z ${checksums_arg[$kind]:-} ]]; } || { [[ -z ${archive_arg[$kind]:-} ]] && [[ -n ${checksums_arg[$kind]:-} ]]; }; then
    die 'each archive needs its checksums file'
  fi
done
for r in "${roots[@]}"; do
  [[ $r == /* && $r != / && $r != *..* && $r =~ ^[a-zA-Z0-9/\ ._()-]+$ ]] || die 'unsafe root path'
done
for n in "${only[@]}"; do [[ $n =~ ^[a-z][a-z0-9-]{0,39}$ ]] || die 'invalid instance name'; done
((EUID==0)) || die 'run the updater as root'
command -v systemctl >/dev/null || die 'systemd required'
command -v flock >/dev/null || die 'flock required'

# The host lock excludes installers for the whole run. install.sh inherits fd 8.
host_lock=/run/lock/mq-exporter.lock
[[ -d /run/lock && ! -L /run/lock ]] || mkdir -m 755 /run/lock
[[ ! -L $host_lock ]] || die 'host lock must not be a symlink'
exec 8>"$host_lock"
flock -n 8 || die 'another installer or updater is active'
export MQ_EXPORTER_LOCK_FD=8

scratch=$(mktemp -d /var/tmp/mq-exporter-update.XXXXXXXX)
trap 'rm -rf -- "$scratch"' EXIT

asset_prefix() { case "$1" in prometheus) printf mq-exporter-dist;; otel) printf mq-otel-dist;; custom) printf mq-exporter-dist-custom;; esac; }
asset_binary() { case "$1" in prometheus) printf mq_prometheus;; otel) printf mq_otel;; custom) printf mq_prometheus_custom;; esac; }
kind_version() { if [[ $1 == custom ]]; then printf '%s' "$custom_version"; else printf '%s' "$native_version"; fi; }

# Same checks as the installer's verify_archive, before anything is extracted.
verify_archive() (
  local archive=$1 checksums=$2 asset=$3 binary=$4 expected actual
  [[ -f $archive && -f $checksums ]] || die 'archive and checksum file required'
  expected=$(awk -v n="$asset" '$2==n {print $1}' "$checksums")
  [[ $expected =~ ^[a-fA-F0-9]{64}$ ]] || die "checksum missing or duplicated for $asset"
  expected=$(printf '%s' "$expected" | tr '[:upper:]' '[:lower:]')
  actual=$(sha256sum "$archive")
  [[ ${actual%% *} == "$expected" ]] || die "archive checksum mismatch for $asset"
  tar -tzf "$archive" > "$archive.names"
  tar -tvzf "$archive" > "$archive.types"
  [[ $(wc -l < "$archive.names") -eq 11 && $(sort -u "$archive.names" | wc -l) -eq 11 ]] || die 'unexpected archive layout'
  while IFS= read -r name; do
    case "$name" in "$binary"|mq-config-check|mq-dist|install.sh|update.sh|diagnose.sh|LICENSE|THIRD-PARTY-NOTICES.txt|build-metadata.json|known-releases.json|sbom.cdx.json) ;; *) die 'unexpected archive path';; esac
  done < "$archive.names"
  while IFS= read -r entry; do [[ ${entry:0:1} == - ]] || die 'archive links and special files forbidden'; done < "$archive.types"
)

declare -A payload=()
prepare() {
  local kind=$1 version asset dir base
  [[ -z ${payload[$kind]:-} ]] || return 0
  version=$(kind_version "$kind")
  asset=$(asset_prefix "$kind")-$version-linux-amd64.tar.gz
  dir=$scratch/$kind
  mkdir "$dir"
  if [[ -n ${archive_arg[$kind]:-} ]]; then
    cp -- "${archive_arg[$kind]}" "$dir/$asset"
    cp -- "${checksums_arg[$kind]}" "$dir/SHA256SUMS"
  else
    base=https://github.com/rknightion/mq-exporter-dist/releases/download/$version
    system_tool curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 600 "$base/$asset" -o "$dir/$asset"
    system_tool curl --fail --silent --show-error --location --proto '=https' --proto-redir '=https' --connect-timeout 20 --max-time 120 "$base/SHA256SUMS" -o "$dir/SHA256SUMS"
  fi
  verify_archive "$dir/$asset" "$dir/SHA256SUMS" "$asset" "$(asset_binary "$kind")"
  mkdir "$dir/payload"
  tar -xzf "$dir/$asset" --no-same-owner --no-same-permissions -C "$dir/payload"
  chmod 755 "$dir" "$dir/payload" "$dir/payload/mq-dist" "$dir/payload/mq-config-check" "$dir/payload/$(asset_binary "$kind")"
  "$dir/payload/mq-dist" inspect "$dir/payload/$(asset_binary "$kind")"
  "$dir/payload/mq-dist" metadata "$dir/payload/build-metadata.json" "$version" linux-amd64
  payload[$kind]=$dir
}

if [[ -n $native_version ]]; then prepare prometheus; tool_kind=prometheus; else prepare custom; tool_kind=custom; fi
tool=${payload[$tool_kind]}/payload/mq-dist
inventory_args=(--known-releases "${payload[$tool_kind]}/payload/known-releases.json")
for r in "${roots[@]}"; do inventory_args+=(--root "$r"); done
"$tool" inventory "${inventory_args[@]}" > "$scratch/inventory"

names=() unmanaged=()
declare -A i_root=() i_dest=() i_unit=() i_exporter=() i_variant=() i_binary=() i_version=() i_port=() i_qmgr=()
declare -A kind=() target=() action=() pre_active=() pre_enabled=() pre_pid=() pre_healthy=() result=() snap=()
while IFS=$'\t' read -r class a b c d e f g h i j k; do
  if [[ $class == unmanaged ]]; then unmanaged+=("$a"$'\t'"$b"$'\t'"$d"$'\t'"$e"); continue; fi
  [[ $class == managed ]] || die 'unexpected inventory output'
  if ((${#only[@]})); then
    wanted=0; for n in "${only[@]}"; do [[ $n != "$a" ]] || wanted=1; done
    ((wanted)) || continue
  fi
  names+=("$a"); i_root[$a]=$b; i_dest[$a]=$c; i_unit[$a]=$d; i_exporter[$a]=$e; i_variant[$a]=$f
  i_binary[$a]=$g; i_version[$a]=$h; i_port[$a]=$j; i_qmgr[$a]=$k
done < "$scratch/inventory"
for n in "${only[@]}"; do [[ -n ${i_dest[$n]:-} ]] || die "instance $n is not a managed instance"; done

service_value() { systemctl show "$1" -p "$2" --value 2>/dev/null || true; }
health_json() { timeout 20 "$tool" health --qmgr "$2" --url "http://127.0.0.1:$1/metrics" 2>/dev/null || true; }
healthy() { [[ $(health_json "$1" "$2") == *'"connected":true'* ]]; }

for n in "${names[@]}"; do
  if [[ ${i_exporter[$n]} == otel ]]; then kind[$n]=otel; elif [[ ${i_variant[$n]} == custom ]]; then kind[$n]=custom; else kind[$n]=prometheus; fi
  target[$n]=$(kind_version "${kind[$n]}")
  pre_active[$n]=$(systemctl is-active "${i_unit[$n]}" 2>/dev/null || true)
  pre_enabled[$n]=$(systemctl is-enabled "${i_unit[$n]}" 2>/dev/null || true)
  pre_pid[$n]=$(service_value "${i_unit[$n]}" MainPID)
  pre_healthy[$n]=no
  if [[ ${i_exporter[$n]} == prometheus && ${pre_active[$n]} == active ]] && healthy "${i_port[$n]}" "${i_qmgr[$n]}"; then pre_healthy[$n]=yes; fi
  if [[ -z ${target[$n]} ]]; then action[$n]=skip-no-target; continue; fi
  if [[ ${i_version[$n]} != unrecorded ]]; then
    cmp=$("$tool" version compare "${i_version[$n]}" "${target[$n]}" 2>/dev/null) || { action[$n]=skip-version-error; continue; }
    if [[ $cmp == 0 ]]; then action[$n]=skip-current; continue; fi
    if [[ $cmp == 1 ]] && ((!allow_downgrade)); then action[$n]=skip-downgrade; continue; fi
  fi
  if [[ $verify == health && ${i_exporter[$n]} == prometheus && ${pre_active[$n]} == active && ${pre_healthy[$n]} == no ]] && ((!include_unhealthy)); then
    action[$n]=skip-unhealthy; continue
  fi
  action[$n]=update
done

printf '%-12s %-24s %-6s %-10s %-7s %-22s %-22s %s\n' INSTANCE ROOT PORT EXPORTER VARIANT CURRENT TARGET ACTION
for n in "${names[@]}"; do
  printf '%-12s %-24s %-6s %-10s %-7s %-22s %-22s %s\n' "$n" "${i_root[$n]}" "${i_port[$n]}" "${i_exporter[$n]}" "${i_variant[$n]}" "${i_version[$n]}" "${target[$n]:--}" "${action[$n]}"
done
for u in "${unmanaged[@]}"; do
  IFS=$'\t' read -r upath uversion uport ureason <<< "$u"
  printf 'UNMANAGED %s version=%s port=%s: %s (not updated)\n' "$upath" "$uversion" "$uport" "$ureason"
done
((${#names[@]})) || printf 'No managed instances found.\n'
if ((dry_run)); then printf 'Dry run: no changes made.\n'; exit 0; fi

# Preflight every target with the exact installer arguments before changing anything.
build_args() {
  local n=$1 dest=${i_dest[$1]} fields user password
  mapfile -t fields < "$dest/identity"
  ((${#fields[@]} >= 8)) || die "identity record incomplete for $n"
  local -a args=(--version "${target[$n]}" --archive "${payload[${kind[$n]}]}/$(asset_prefix "${kind[$n]}")-${target[$n]}-linux-amd64.tar.gz"
    --checksums "${payload[${kind[$n]}]}/SHA256SUMS" --instance "$n" --root "${i_root[$n]}" --qmgr "${fields[0]}"
    --service-user "${fields[2]}" --mq-path "${fields[3]}" --mode "${fields[4]}" --no-start)
  if [[ ${kind[$n]} == otel ]]; then
    ((${#fields[@]} == 11)) || die "otel identity record incomplete for $n"
    args+=(--exporter otel --otlp-endpoint "${fields[9]}")
    [[ ${fields[10]} != 1 ]] || args+=(--otlp-insecure)
  else
    args+=(--exporter prometheus --port "${fields[1]}")
  fi
  [[ -z ${fields[5]} ]] || args+=(--channel "${fields[5]}")
  [[ -z ${fields[6]} ]] || args+=(--conn-name "${fields[6]}")
  [[ -z ${fields[7]} ]] || args+=(--ccdt "${fields[7]}")
  user=$("$tool" config-field "$dest/config.json" connection.user) || die "unreadable configuration for $n"
  password=$("$tool" config-field "$dest/config.json" connection.passwordFile) || die "unreadable configuration for $n"
  [[ -z $user || -z $password ]] || args+=(--user "$user" --password-file "$password")
  ((!allow_downgrade)) || args+=(--allow-downgrade)
  printf '%s\0' "${args[@]}"
}
targets=()
for n in "${names[@]}"; do
  [[ ${action[$n]} == update ]] || continue
  prepare "${kind[$n]}"
  build_args "$n" > "$scratch/args-$n"
  mapfile -d '' -t args < "$scratch/args-$n"
  if ! bash "${payload[${kind[$n]}]}/payload/install.sh" "${args[@]}" --preflight-only > "$scratch/preflight-$n.log" 2>&1; then
    cat "$scratch/preflight-$n.log" >&2
    die "preflight failed for $n; no instance was changed"
  fi
  targets+=("$n")
done
((${#targets[@]})) || { printf 'Nothing to update.\n'; exit 0; }

files_for() {
  local dest=$1
  printf '%s\n' "$dest/mq_prometheus" "$dest/mq_prometheus_custom" "$dest/mq_otel" "$dest/mq-config-check" "$dest/mq-dist" \
    "$dest/config.json" "$dest/identity" "$dest/port" "$dest/variant" "$dest/release" "/etc/systemd/system/$2"
}
file_record() {
  local p=$1
  if [[ -e $p || -L $p ]]; then
    [[ -f $p && ! -L $p ]] || return 1
    local sum label=-
    sum=$(sha256sum "$p")
    if selinux_active; then label=$(stat -c %C "$p"); fi
    printf '1\t%s\t%s\t%s' "${sum%% *}" "$(stat -c '%u %g %a' "$p")" "$label"
  else
    printf '0'
  fi
}
# Snapshots live beside the instances, on the same filesystem, never followed through links.
snapshot() {
  local n=$1 base=${i_root[$1]}/.update-backups dir i=0 p record copy
  if [[ -e $base || -L $base ]]; then
    [[ -d $base && ! -L $base && $(stat -c %u "$base") == 0 && $(realpath -m "$base") == "$base" ]] || { printf 'ERROR: %s must be a root-owned directory\n' "$base" >&2; return 1; }
    (( (8#$(stat -c %a "$base") & 0077) == 0 )) || { printf 'ERROR: %s must be private\n' "$base" >&2; return 1; }
  else
    mkdir -m 700 "$base" || return 1
  fi
  dir=$(mktemp -d "$base/$n.XXXXXXXX") || return 1
  # Called from a condition, where errexit is off: check every step explicitly.
  mkdir "$dir/files" "$dir/created" || return 1
  snap[$n]=$dir
  while IFS= read -r p; do
    record=$(file_record "$p") || { printf 'ERROR: unexpected file type at %s\n' "$p" >&2; return 1; }
    if [[ $record != 0 ]]; then
      cp --preserve=mode,ownership,timestamps -- "$p" "$dir/files/$i" || return 1
      copy=$(sha256sum "$dir/files/$i") || return 1
      [[ $record == 1$'\t'"${copy%% *}"$'\t'* ]] || { printf 'ERROR: snapshot copy of %s does not match\n' "$p" >&2; return 1; }
    fi
    printf '%s\t%s\t%s\n' "$i" "$p" "$record" >> "$dir/manifest" || return 1
    i=$((i+1))
  done < <(files_for "${i_dest[$n]}" "${i_unit[$n]}")
}
journal() { printf '%s %s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$2" >> "${snap[$1]}/journal"; }

# Test-only fault injection, honoured only when an administrator creates the marker.
fault() {
  [[ -f /etc/mq-exporter-update-test-faults && ! -L /etc/mq-exporter-update-test-faults ]] || return 0
  case "${MQ_DIST_UPDATE_TEST_FAULT:-}" in
    "$1:$2") printf 'TEST FAULT injected for %s at %s\n' "$1" "$2" >&2; return 1;;
    "$1:$2:hang")
      # Simulates an interrupted session; the signal trap performs the rollback.
      printf 'TEST FAULT waiting for a signal at %s %s\n' "$1" "$2" >&2
      : > /run/mq-dist-update-test-waiting
      sleep 120 8>&- & fault_pid=$!
      wait "$fault_pid"; return 1;;
  esac
}

# The service must run the expected file; after an update, also a new process.
wait_started() {
  local n=$1 binary=$2 new_pid=$3 deadline pid exe
  deadline=$((SECONDS+health_timeout))
  while ((SECONDS<deadline)); do
    pid=$(service_value "${i_unit[$n]}" MainPID)
    if [[ $pid =~ ^[1-9][0-9]*$ && ( $new_pid == 0 || $pid != "${pre_pid[$n]}" ) && $(systemctl is-active "${i_unit[$n]}" 2>/dev/null || true) == active ]]; then
      exe=$(readlink "/proc/$pid/exe" 2>/dev/null || true)
      [[ $exe == "${i_dest[$n]}/$binary" ]] && return 0
    fi
    sleep 1
  done
  return 1
}
settled() {
  local n=$1 pid restarts
  pid=$(service_value "${i_unit[$n]}" MainPID); restarts=$(service_value "${i_unit[$n]}" NRestarts)
  sleep "$settle"
  [[ $(systemctl is-active "${i_unit[$n]}" 2>/dev/null || true) == active && $(service_value "${i_unit[$n]}" MainPID) == "$pid" && $(service_value "${i_unit[$n]}" NRestarts) == "$restarts" ]]
}
wait_healthy() {
  local n=$1 deadline
  deadline=$((SECONDS+health_timeout))
  while ((SECONDS<deadline)); do healthy "${i_port[$n]}" "${i_qmgr[$n]}" && return 0; sleep 2; done
  return 1
}
verify_update() {
  local n=$1 binary json
  [[ -f ${i_dest[$n]}/release && $(head -n 1 "${i_dest[$n]}/release") == "${target[$n]}" ]] || { journal "$n" 'release record not updated'; return 1; }
  binary=$(sed -n 4p "${i_dest[$n]}/release")
  [[ $(systemctl is-enabled "${i_unit[$n]}" 2>/dev/null || true) == "${pre_enabled[$n]}" ]] || { journal "$n" 'enablement changed'; return 1; }
  [[ ${pre_active[$n]} == active ]] || return 0
  wait_started "$n" "$binary" 1 || { journal "$n" 'new binary did not start'; return 1; }
  settled "$n" || { journal "$n" 'service did not stay running'; return 1; }
  if [[ $verify == health && ${pre_healthy[$n]} == yes ]]; then
    wait_healthy "$n" || { journal "$n" 'MQ connection not healthy after update'; return 1; }
    if [[ ${kind[$n]} == custom ]]; then
      json=$(health_json "${i_port[$n]}" "${i_qmgr[$n]}")
      if [[ $json != *'"queue_series":0'* && $json == *'"depth_high_limit_series":0'* ]]; then
        journal "$n" 'custom QDEPTHHI gauge missing'; return 1
      fi
    fi
  fi
}

restore_files() {
  local n=$1 dir=${snap[$1]} idx p existed sum owner label rest
  while IFS=$'\t' read -r idx p existed sum owner label rest; do
    if [[ $existed == 0 ]]; then
      if [[ -e $p || -L $p ]]; then mv -- "$p" "$dir/created/$idx"; fi
    else
      "$tool" replace "$dir/files/$idx" "$p" > /dev/null
      read -r uid gid mode <<< "$owner"
      chown "$uid:$gid" "$p"; chmod "$mode" "$p"
      # Restore the recorded context exactly, so the manifest comparison is meaningful.
      if [[ $label != - ]] && selinux_active; then system_tool chcon -- "$label" "$p"; fi
    fi
  done < "$dir/manifest"
}
manifest_matches() {
  local idx p expected actual rest
  while IFS=$'\t' read -r idx p rest; do
    expected=$rest
    actual=$(file_record "$p") || return 1
    [[ $actual == "$expected" ]] || return 1
  done < "${snap[$1]}/manifest"
}
rollback() {
  local n=$1 old
  journal "$n" 'rollback started'
  restore_files "$n" || return 1
  systemctl daemon-reload
  case "${pre_enabled[$n]}" in enabled) systemctl enable "${i_unit[$n]}" >/dev/null 2>&1;; disabled) systemctl disable "${i_unit[$n]}" >/dev/null 2>&1;; esac
  if [[ ${pre_active[$n]} == active ]]; then systemctl restart "${i_unit[$n]}"; else systemctl stop "${i_unit[$n]}" 2>/dev/null || true; fi
  manifest_matches "$n" || { journal "$n" 'restored files differ from the snapshot'; return 1; }
  [[ $(systemctl is-enabled "${i_unit[$n]}" 2>/dev/null || true) == "${pre_enabled[$n]}" ]] || return 1
  if [[ ${pre_active[$n]} == active ]]; then
    old=${i_binary[$n]}
    wait_started "$n" "$old" 0 || return 1
    if [[ $verify == health && ${pre_healthy[$n]} == yes ]]; then wait_healthy "$n" || return 1; fi
  fi
  journal "$n" 'rollback complete'
}

current='' fault_pid=''
# shellcheck disable=SC2317,SC2329 # invoked by the signal trap
interrupted() {
  trap '' INT TERM HUP
  [[ -z $fault_pid ]] || kill "$fault_pid" 2>/dev/null || true
  if [[ -n $current ]]; then
    journal "$current" 'interrupted'
    if rollback "$current"; then result[$current]=rolled-back; else result[$current]=ROLLBACK-FAILED; fi
  fi
  report
  if [[ -n $current && ${result[$current]} == ROLLBACK-FAILED ]]; then exit 3; fi
  exit 2
}
report() {
  printf '\n%-12s %-22s %-22s %s\n' INSTANCE FROM TO RESULT
  for n in "${names[@]}"; do
    local r=${result[$n]:-${action[$n]}}
    [[ $r != update ]] || r=not-attempted
    printf '%-12s %-22s %-22s %s%s\n' "$n" "${i_version[$n]}" "${target[$n]:--}" "$r" "${snap[$n]:+ (snapshot ${snap[$n]})}"
  done
}
trap interrupted INT TERM HUP

status=0
for n in "${targets[@]}"; do
  if ! snapshot "$n"; then result[$n]=snapshot-failed; status=2; break; fi
  current=$n
  journal "$n" "update ${i_version[$n]} -> ${target[$n]} started"
  mapfile -d '' -t args < "$scratch/args-$n"
  ok=1
  if ! bash "${payload[${kind[$n]}]}/payload/install.sh" "${args[@]}" > "${snap[$n]}/install.log" 2>&1; then
    journal "$n" 'installer failed'; ok=0
  fi
  if ((ok)) && [[ ${pre_enabled[$n]} == disabled ]]; then systemctl disable "${i_unit[$n]}" >/dev/null 2>&1 || ok=0; fi
  if ((ok)) && [[ ${pre_active[$n]} == active ]]; then systemctl restart "${i_unit[$n]}" || ok=0; fi
  if ((ok)) && ! fault "$n" replaced; then ok=0; fi
  if ((ok)) && ! verify_update "$n"; then ok=0; fi
  if ((ok)); then
    result[$n]=updated; journal "$n" 'update verified'; current=''
    continue
  fi
  if rollback "$n"; then result[$n]=rolled-back; status=2; else result[$n]=ROLLBACK-FAILED; status=3; fi
  current=''
  break
done
report
case $status in
  0) printf 'All targeted instances updated and verified.\n';;
  2) printf 'PARTIAL: one instance failed and was left or rolled back to its previous state; remaining instances were not attempted.\n';;
  3) printf 'ROLLBACK FAILED: restore the instance manually from its snapshot manifest (see docs).\n';;
esac
exit "$status"
