#!/usr/bin/env bash
# Only for a fresh, explicitly authorized disposable native test VM.
set -euo pipefail
[[ ${MQ_DIST_DISPOSABLE_TEST:-} == 1 && $EUID == 0 ]] || exit 2
input=/var/lib/mq-dist-test-input
root='/opt/mq exporter'
[[ -d $input && ! -e $root ]] || exit 2
id mqmon >/dev/null 2>&1 && exit 2
useradd --system --no-create-home --shell /sbin/nologin mqmon
cat /etc/redhat-release
uname -r
getconf GNU_LIBC_VERSION
getenforce
retry() {
  local instance=$1 expected=$2 unit count deadline
  unit=mq-exporter-$instance.service
  count=$(systemctl show "$unit" -p NRestarts --value)
  deadline=$((SECONDS+55))
  while ((SECONDS<deadline)); do
    if (( $(systemctl show "$unit" -p NRestarts --value) > count )) &&
      [[ $(systemctl show "$unit" -p ExecMainStatus --value) == "$expected" ]]; then
      systemctl is-enabled "$unit"
      printf 'PASS: actual exporter restart and expected unavailable-MQ exit: %s\n' "$instance"
      return
    fi
    sleep 1
  done
  journalctl -u "$unit" --no-pager -n 15
  return 1
}
stop_instance() {
  local unit=mq-exporter-$1.service
  systemctl stop "$unit"
  [[ $(systemctl show "$unit" -p ActiveState --value) == inactive ]]
  [[ $(systemctl show "$unit" -p MainPID --value) == 0 ]]
}
args=(--root "$root" --service-user mqmon --mq-path /opt/mqm)
bash "$input/rc1/install.sh" "${args[@]}" --version v0.1.0-rc.1 --instance qm1 --qmgr QM1 --archive "$input/rc1-linux.tar.gz" --checksums "$input/SHA256SUMS"
retry qm1 10
stop_instance qm1
systemctl start mq-exporter-qm1
config=$root/qm1/config.json
[[ $(stat -c '%a:%U' "$config") == 600:mqmon ]]
[[ $(systemctl show mq-exporter-qm1 -p User --value) == mqmon ]]
[[ $(systemctl show mq-exporter-qm1 -p ProtectHome --value) == yes ]]
[[ $(systemctl show mq-exporter-qm1 -p ProtectSystem --value) == strict ]]
sed -i 's/"pollInterval": "30s"/"pollInterval": "20s"/' "$config"
grep -q '"pollInterval": "20s"' "$config"
config_hash=$(sha256sum "$config")
old_binary=$(sha256sum "$root/qm1/mq_prometheus"); old_binary=${old_binary%% *}
upgrade=(--version v0.1.0-rc.3 --archive "$input/prometheus-linux.tar.gz" --checksums "$input/SHA256SUMS")
bash "$input/prometheus/install.sh" "${args[@]}" "${upgrade[@]}" --instance qm1 --qmgr QM1
[[ $(sha256sum "$config") == "$config_hash" ]]
cmp "$root/qm1/mq_prometheus" "$input/prometheus/mq_prometheus"
backup_found=0
for backup in "$root/qm1/"mq_prometheus.bak-*; do
  digest=$(sha256sum "$backup"); [[ ${digest%% *} != "$old_binary" ]] || backup_found=1
done
[[ $backup_found == 1 ]]
retry qm1 10
printf 'PASS: native running-service rc.1 to rc.3 upgrade, binary backup and config preservation\n'
if bash "$input/prometheus/install.sh" "${args[@]}" "${upgrade[@]}" --instance qm1 --qmgr QM2 > "$input/rejected.log" 2>&1; then exit 1; fi
grep -q 'instance identity differs' "$input/rejected.log"
[[ $(sha256sum "$config") == "$config_hash" ]]
bash "$input/prometheus/install.sh" "${args[@]}" "${upgrade[@]}" --instance qm2 --qmgr QM2 --port 9158 --mode client --channel APP.SVRCONN --conn-name '127.0.0.1(1)'
retry qm2 10
[[ $(sha256sum "$config") == "$config_hash" ]]
bash "$input/otel/install.sh" "${args[@]}" --version v0.1.0-rc.3 --instance otel --qmgr QM1 --exporter otel --otlp-endpoint https://otel.example.com:4318 --archive "$input/otel-linux.tar.gz" --checksums "$input/SHA256SUMS"
retry otel 1
[[ $(stat -c '%a:%U' "$root/otel/config.json") == 600:mqmon ]]
for instance in qm1 qm2 otel; do
  stop_instance "$instance"
  systemctl start "mq-exporter-$instance.service"
done
printf 'PASS: separate packages, instance isolation, native systemd stop/start and sandbox. Services retained for reboot validation. No live MQ or metric delivery claimed.\n'
