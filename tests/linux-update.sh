#!/usr/bin/env bash
# Runs only inside a disposable EL8 container; no host service changes.
# Multi-instance updater regression: mixed versions, variants and roots,
# dry-run, preflight failure, success, rollback and interruption.
# shellcheck disable=SC2015 # "check && check || fail" is intended; fail exits
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
source_archive=$1 fake=$2 fake_bad=$3
dnf -q -y install shadow-utils util-linux procps-ng >/dev/null
useradd --system mqmon
mkdir /opt/mqm
cp -R /sdk-input/. /opt/mqm/
chown -R root:root /opt/mqm
chmod go-w /opt/mqm
mv /usr/bin/systemctl /usr/bin/systemctl.container-original
cp /project/tests/mock-systemctl.sh /usr/bin/systemctl
chmod 755 /usr/bin/systemctl
work=/var/lib/update-test
mkdir -p "$work/src"
tar -xzf "$source_archive" -C "$work/src"
# Always test the updater and installer from this checkout.
cp /project/install/install.sh /project/install/update.sh "$work/src/"
pass() { printf 'PASS: %s\n' "$*"; }
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }

# repack KIND VERSION FAKE: a release archive holding a fake exporter binary.
repack() {
  local kind=$1 version=$2 exe=$3 prefix binary dir name
  case "$kind" in
    prometheus) prefix=mq-exporter-dist; binary=mq_prometheus;;
    otel) prefix=mq-otel-dist; binary=mq_otel;;
    custom) prefix=mq-exporter-dist-custom; binary=mq_prometheus_custom;;
  esac
  dir=$work/pack-$kind-$version
  mkdir "$dir"
  cp "$work/src"/{mq-config-check,mq-dist,install.sh,update.sh,diagnose.sh,LICENSE,THIRD-PARTY-NOTICES.txt,known-releases.json,sbom.cdx.json} "$dir/"
  cp "$exe" "$dir/$binary"
  sed -E 's/"distribution_version": "[^"]+"/"distribution_version": "'"$version"'"/' "$work/src/build-metadata.json" > "$dir/build-metadata.json"
  chmod 755 "$dir/$binary" "$dir/mq-config-check" "$dir/mq-dist" "$dir/install.sh" "$dir/update.sh" "$dir/diagnose.sh"
  name=$prefix-$version-linux-amd64.tar.gz
  (cd "$dir" && tar -czf "$work/$name" -- *)
  (cd "$work" && sha256sum "$name" >> SHA256SUMS)
}
repack prometheus v6.0.0-1 "$fake"; repack prometheus v6.0.0-2 "$fake"
repack otel v6.0.0-1 "$fake"; repack otel v6.0.0-2 "$fake"
repack custom v6.0.0-custom-1 "$fake"; repack custom v6.0.0-custom-2 "$fake"
repack custom v6.0.0-custom-3 "$fake_bad"
sums=$work/SHA256SUMS
asset() { case "$1" in prometheus) printf '%s/mq-exporter-dist-%s-linux-amd64.tar.gz' "$work" "$2";; otel) printf '%s/mq-otel-dist-%s-linux-amd64.tar.gz' "$work" "$2";; custom) printf '%s/mq-exporter-dist-custom-%s-linux-amd64.tar.gz' "$work" "$2";; esac; }
install_instance() {
  local kind=$1 version=$2; shift 2
  local extra=()
  [[ $kind != otel ]] || extra=(--exporter otel --otlp-endpoint https://otel.example.com:4318)
  bash "$work/src/install.sh" --version "$version" --archive "$(asset "$kind" "$version")" --checksums "$sums" --service-user mqmon --no-start "${extra[@]}" "$@" > /dev/null
}
install_instance prometheus v6.0.0-1 --instance qm1 --qmgr QM1 --port 9157
install_instance custom v6.0.0-custom-1 --instance qm2 --qmgr QM2 --port 9158
install_instance custom v6.0.0-custom-1 --instance qm3 --qmgr QM3 --port 9159 --root '/srv/mq x'
install_instance prometheus v6.0.0-1 --instance qm4 --qmgr QM4 --port 9160 --root /srv/mqx
install_instance otel v6.0.0-1 --instance qm5 --qmgr QM5 --root /srv/mqx
install_instance prometheus v6.0.0-1 --instance qm6 --qmgr QM6 --port 9161 --root /srv/mqx
# qm1 has the on-disk layout of a v6.0.0 install: no variant or release record.
rm /opt/mq-exporter/qm1/variant /opt/mq-exporter/qm1/release
for i in qm1 qm2 qm3 qm4 qm5; do systemctl start "mq-exporter-$i.service"; done
systemctl disable mq-exporter-qm6.service
# Operator tuning that every update must preserve.
sed -i 's/"pollInterval": "30s"/"pollInterval": "45s"/' /opt/mq-exporter/qm2/config.json
# An exporter copy outside the managed layout.
mkdir -p /usr/local/lib/mqx-manual
cp "$fake" /usr/local/lib/mqx-manual/mq_prometheus
printf '{"connection":{"queueManager":"QM9"},"prometheus":{"port":"9199"}}' > "$work/manual.json"
setsid /usr/local/lib/mqx-manual/mq_prometheus -f "$work/manual.json" > /dev/null 2>&1 < /dev/null &
manual_pid=$!
sleep 1

dests=(/opt/mq-exporter/qm1 /opt/mq-exporter/qm2 '/srv/mq x/qm3' /srv/mqx/qm4 /srv/mqx/qm5 /srv/mqx/qm6)
fingerprint() {
  local d
  for d in "${dests[@]}"; do (cd "$d" && sha256sum -- * | sort -k2 && stat -c '%n %u %g %a' -- *); done
  cat /etc/systemd/system/mq-exporter-qm*.service
}
config_fingerprint() { local d; for d in "${dests[@]}"; do sha256sum "$d/config.json" "$d/identity" "$d/port"; done; }
pid() { systemctl show "mq-exporter-$1.service" -p MainPID --value; }
release() { head -n 1 "$1/release"; }
update() { bash "$work/src/update.sh" --native-archive "$(asset prometheus "$1")" --native-checksums "$sums" --native-version "$1" \
  --otel-archive "$(asset otel "$1")" --otel-checksums "$sums" \
  --custom-archive "$(asset custom "$2")" --custom-checksums "$sums" --custom-version "$2" \
  --root /srv/mqx --root '/srv/mq x' --settle 1 --health-timeout 15 "${@:3}"; }
expect_exit() { local want=$1; shift; set +e; "$@" > "$work/out" 2>&1; local got=$?; set -e; [[ $got == "$want" ]] || { cat "$work/out"; fail "expected exit $want, got $got: $*"; }; }

before=$(fingerprint); configs=$(config_fingerprint)
expect_exit 0 update v6.0.0-2 v6.0.0-custom-2 --dry-run
grep -q 'qm1 .*v6.0.0-1 .*v6.0.0-2 .*update' "$work/out" || { cat "$work/out"; fail 'legacy install not identified from known hash or not planned'; }
grep -q 'qm3 .*/srv/mq x .*custom .*v6.0.0-custom-1 .*v6.0.0-custom-2 .*update' "$work/out" || fail 'alternate-root custom instance not planned'
grep -q 'qm5 .*otel .*v6.0.0-1 .*v6.0.0-2 .*update' "$work/out" || fail 'otel instance not planned'
grep -q 'UNMANAGED /usr/local/lib/mqx-manual/mq_prometheus version=unrecorded port=9199' "$work/out" || { cat "$work/out"; fail 'unmanaged copy not reported'; }
[[ $(fingerprint) == "$before" ]] || fail 'dry run changed files'
pass 'dry-run inventory across roots, variants, otel and an unmanaged copy'

chmod 777 '/srv/mq x'
expect_exit 1 update v6.0.0-2 v6.0.0-custom-2
grep -q 'preflight failed for qm3; no instance was changed' "$work/out" || { cat "$work/out"; fail 'preflight failure not reported'; }
chmod 755 '/srv/mq x'
[[ $(fingerprint) == "$before" ]] || fail 'preflight failure changed files'
pass 'preflight failure changes nothing'

touch /etc/mq-exporter-update-test-faults
qm2_pid=$(pid qm2)
MQ_DIST_UPDATE_TEST_FAULT=qm2:replaced expect_exit 2 update v6.0.0-2 v6.0.0-custom-2
grep -q '^qm1 .*updated' "$work/out" && grep -q '^qm2 .*rolled-back' "$work/out" && grep -q '^qm3 .*not-attempted' "$work/out" || { cat "$work/out"; fail 'partial result not reported'; }
[[ $(release /opt/mq-exporter/qm2) == v6.0.0-custom-1 && $(release /opt/mq-exporter/qm1) == v6.0.0-2 ]] || fail 'release records after rollback'
[[ $(readlink "/proc/$(pid qm2)/exe") == /opt/mq-exporter/qm2/mq_prometheus_custom && $(pid qm2) != "$qm2_pid" ]] || fail 'rolled-back service not running'
[[ $(release '/srv/mq x/qm3') == v6.0.0-custom-1 ]] || fail 'later instance was changed'
pass 'failed instance rolled back, earlier instance kept, later instances not attempted'

MQ_DIST_UPDATE_TEST_FAULT=qm2:replaced:hang bash "$work/src/update.sh" --custom-archive "$(asset custom v6.0.0-custom-2)" --custom-checksums "$sums" \
  --custom-version v6.0.0-custom-2 --root /srv/mqx --root '/srv/mq x' --settle 1 --health-timeout 15 --instance qm2 > "$work/out" 2>&1 &
updater=$!
for _ in $(seq 100); do [[ -e /run/mq-dist-update-test-waiting ]] && break; sleep 0.2; done
[[ -e /run/mq-dist-update-test-waiting ]] || { cat "$work/out"; fail 'fault point not reached'; }
kill -TERM "$updater"
set +e; wait "$updater"; got=$?; set -e
[[ $got == 2 ]] && grep -q '^qm2 .*rolled-back' "$work/out" || { cat "$work/out"; fail "interrupted update not rolled back (exit $got)"; }
[[ $(release /opt/mq-exporter/qm2) == v6.0.0-custom-1 ]] || fail 'interrupted instance kept the new release'
grep -q interrupted /opt/mq-exporter/.update-backups/qm2.*/journal || fail 'journal did not record the interruption'
pass 'interrupted update rolled back by the signal trap'
rm /etc/mq-exporter-update-test-faults

expect_exit 0 update v6.0.0-2 v6.0.0-custom-2
for d in /opt/mq-exporter/qm2 '/srv/mq x/qm3'; do [[ $(release "$d") == v6.0.0-custom-2 && $(<"$d/variant") == custom ]] || fail "custom release for $d"; done
for d in /opt/mq-exporter/qm1 /srv/mqx/qm4 /srv/mqx/qm5 /srv/mqx/qm6; do [[ $(release "$d") == v6.0.0-2 && $(<"$d/variant") == native ]] || fail "native release for $d"; done
[[ $(config_fingerprint) == "$configs" ]] || fail 'configuration, identity or port changed'
grep -q '"pollInterval": "45s"' /opt/mq-exporter/qm2/config.json || fail 'operator tuning lost'
[[ $(stat -c %U /opt/mq-exporter/qm2/config.json) == mqmon ]] || fail 'config ownership changed'
[[ $(systemctl is-enabled mq-exporter-qm6.service || true) == disabled && $(pid qm6) == 0 ]] || fail 'disabled, stopped instance was enabled or started'
[[ $(readlink "/proc/$(pid qm3)/exe") == '/srv/mq x/qm3/mq_prometheus_custom' ]] || fail 'alternate-root instance not running the new file'
kill -0 "$manual_pid" && cmp -s "$fake" /usr/local/lib/mqx-manual/mq_prometheus || fail 'unmanaged copy was touched'
pass 'all instances updated with configuration, identity, ports, enablement and state preserved'

expect_exit 0 update v6.0.0-2 v6.0.0-custom-2
grep -q 'Nothing to update' "$work/out" && ! grep -q ' update$' "$work/out" || { cat "$work/out"; fail 'rerun was not idempotent'; }
expect_exit 0 update v6.0.0-1 v6.0.0-custom-1
grep -q 'qm1 .*skip-downgrade' "$work/out" || fail 'downgrade not refused'
pass 'rerun is idempotent and downgrades are refused'

qm3_pid=$(pid qm3)
expect_exit 2 bash "$work/src/update.sh" --custom-archive "$(asset custom v6.0.0-custom-3)" --custom-checksums "$sums" --custom-version v6.0.0-custom-3 \
  --root /srv/mqx --root '/srv/mq x' --settle 1 --health-timeout 10
grep -q '^qm2 .*updated' "$work/out" && grep -q '^qm3 .*rolled-back' "$work/out" || { cat "$work/out"; fail 'health failure not rolled back'; }
[[ $(release '/srv/mq x/qm3') == v6.0.0-custom-2 && $(pid qm3) != "$qm3_pid" ]] || fail 'health rollback state'
/opt/mq-exporter/qm1/mq-dist health --qmgr QM3 --url http://127.0.0.1:9159/metrics | grep -q '"connected":true' || fail 'rolled-back instance unhealthy'
pass 'post-update health failure rolled back to the healthy release'

if bash "$work/src/install.sh" --version v6.0.0-custom-2 --archive "$(asset custom v6.0.0-custom-2)" --checksums "$sums" --service-user mqmon --no-start --instance qm1 --qmgr QM1 --port 9157 > "$work/out" 2>&1; then fail 'variant change accepted without --change-variant'; fi
grep -q 'explicit --change-variant required' "$work/out" || fail 'variant guard message'
bash "$work/src/install.sh" --version v6.0.0-custom-2 --archive "$(asset custom v6.0.0-custom-2)" --checksums "$sums" --service-user mqmon --no-start --instance qm1 --qmgr QM1 --port 9157 --change-variant > /dev/null
[[ -f /opt/mq-exporter/qm1/mq_prometheus && $(<"/opt/mq-exporter/qm1/variant") == custom ]] || fail 'variant change'
grep -q 'qm1/mq_prometheus_custom" -f' /etc/systemd/system/mq-exporter-qm1.service || fail 'unit not switched to the custom binary'
if bash "$work/src/install.sh" --version v6.0.0-custom-1 --archive "$(asset custom v6.0.0-custom-1)" --checksums "$sums" --service-user mqmon --no-start --instance qm1 --qmgr QM1 --port 9157 > "$work/out" 2>&1; then fail 'installer downgrade accepted'; fi
pass 'installer variant and downgrade guards'
printf 'Linux updater integration: PASS; service commands mocked, fake exporter, no live MQ\n'
