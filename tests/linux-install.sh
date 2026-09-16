#!/usr/bin/env bash
# Runs only inside a disposable EL8 container; no host service changes.
set -euo pipefail
export PATH=/usr/sbin:/usr/bin:/sbin:/bin
dnf -q -y install shadow-utils util-linux >/dev/null
useradd --system mqmon
mv /usr/bin/systemctl /usr/bin/systemctl.container-original
cp /project/tests/mock-systemctl.sh /usr/bin/systemctl
chmod 755 /usr/bin/systemctl
archive=$1
version=$2
args=(--version "$version" --archive "$archive" --checksums "$archive.sha256" --service-user mqmon --no-start)
bash /project/install/install.sh "${args[@]}" --instance qm1 --qmgr QM1
old=$(sha256sum /opt/mq-exporter/qm1/mq_prometheus)
expect_failure() { if "$@" >/tmp/expected-failure.log 2>&1; then printf 'Expected failure was accepted\n' >&2; exit 1; fi; }
expect_failure bash /project/install/install.sh "${args[@]}" --instance qm1 --qmgr QM2
expect_failure bash /project/install/install.sh "${args[@]}" --instance qm2 --qmgr QM2
expect_failure bash /project/install/install.sh "${args[@]}" --instance qm2 --qmgr QM2 --port 65536
expect_failure bash /project/install/install.sh "${args[@]}" --instance qm1 --qmgr QM1 --queues ', ,'
[[ $(sha256sum /opt/mq-exporter/qm1/mq_prometheus) == "$old" ]]
bash /project/install/install.sh "${args[@]}" --instance qm2 --qmgr QM2 --port 9158
[[ -f /opt/mq-exporter/qm2/config.json ]]
bash /project/install/install.sh "${args[@]}" --instance qm1 --qmgr QM1
compgen -G '/opt/mq-exporter/qm1/mq_prometheus.bak-*' >/dev/null
mkdir '/tmp/payload with spaces'
tar -xzf "$archive" -C '/tmp/payload with spaces'
cp '/tmp/payload with spaces/mq-dist' '/tmp/payload with spaces/mq_prometheus'
name=$(basename "$archive")
(cd '/tmp/payload with spaces'; tar -czf "/tmp/$name" -- *)
(cd /tmp; sha256sum "$name" > smoke.SHA256SUMS)
expect_failure bash /project/install/install.sh --version "$version" --archive "/tmp/$name" --checksums /tmp/smoke.SHA256SUMS --service-user mqmon --instance qm1 --qmgr QM1
[[ $(sha256sum /opt/mq-exporter/qm1/mq_prometheus) == "$old" ]]
bash /project/install/install.sh "${args[@]}" --root '/opt/mq exporter' --instance qm3 --qmgr QM3 --port 9159
printf 'Linux installer integration: PASS; service commands mocked, no live MQ\n'
