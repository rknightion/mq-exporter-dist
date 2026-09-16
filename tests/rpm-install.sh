#!/usr/bin/env bash
# Transaction/layout test only. No native SELinux, systemd or live MQ claim.
set -euo pipefail
[[ -e /.dockerenv && ${MQ_DIST_RPM_TEST:-} == 1 ]] || exit 1
[[ ! -e /etc/mq-prometheus && ! -e /etc/mq-otel ]] || exit 1
mv /usr/bin/systemctl /usr/bin/systemctl.rpm-test-original
install -m755 /project/tests/rpm-systemctl.sh /usr/bin/systemctl
rpm -ivh /packages/*.rpm
test -x /usr/libexec/mq-prometheus/mq_prometheus
test -x /usr/libexec/mq-otel/mq_otel
if grep -E 'start|enable|preset' /tmp/rpm-systemctl-calls; then exit 1; fi
printf 'synthetic preserved config\n' > /etc/mq-prometheus/qm1.json
printf 'synthetic preserved config\n' > /etc/mq-otel/qm1.json
rpm -Uvh --replacepkgs /packages/*.rpm
grep -Fx 'synthetic preserved config' /etc/mq-prometheus/qm1.json
grep -Fx 'synthetic preserved config' /etc/mq-otel/qm1.json
if grep -E 'stop|restart|enable|preset' /tmp/rpm-systemctl-calls; then exit 1; fi
rpm -e mq-prometheus
test -f /etc/mq-prometheus/qm1.json
test -x /usr/libexec/mq-otel/mq_otel
grep -Fx 'stop mq-prometheus@*.service' /tmp/rpm-systemctl-calls
if grep -Fx 'stop mq-otel@*.service' /tmp/rpm-systemctl-calls; then exit 1; fi
rpm -e mq-otel
test -f /etc/mq-otel/qm1.json
grep -Fx 'stop mq-otel@*.service' /tmp/rpm-systemctl-calls
printf '%s\n' 'PASS: RPM install/reinstall/remove, separate ownership, retained configuration and scoped service calls (mock systemctl; SELinux not tested)'
