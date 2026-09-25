Community distribution of IBM's unchanged mq_prometheus and mq_otel
v6.0.0, delivered as separate packages. Install only the exporter you need.
This is not an official IBM release or an IBM-supported product. It is not
affiliated with IBM or Grafana Labs and is provided without warranty.

Prometheus archives use the `mq-exporter-dist-` prefix; OpenTelemetry archives use
`mq-otel-dist-`. Each has a Linux tar.gz and Windows ZIP, with its own configuration
reader. OTel requires an explicitly configured OTLP receiver and does not expose
the Prometheus health endpoint. Neither package installs or changes a Prometheus
server or Grafana Alloy. Their configuration is supplied only as examples.

Initial targets: Linux x86-64 on RHEL 8.10 / glibc 2.28 and RHEL 9.x / glibc 2.34,
with an existing IBM MQ 9.3.0.27 runtime; Windows Server 2019 amd64, with its MQ
runtime version independently confirmed. Platform support remains provisional.

Archives contain precompiled executables, installers, notices, SBOM and build
metadata. Linux archives also include `update.sh`, which updates every managed
instance on a host with per-instance snapshots and rollback. IBM MQ SDK/runtime libraries are not included. SHA256SUMS and GitHub
provenance cover these archive bytes. Review the compatibility matrix and
per-artifact metadata before use. Native RHEL and Server 2019 lifecycle checks
and live MQ 9.3.0.35 trial checks are described in the
[compatibility guide](https://rknightion.github.io/mq-exporter-dist/compatibility/).
Exact MQ 9.3.0.27 server/local-bindings acceptance remains outstanding.
Build metadata records build-time checks, not
subsequent native validation.

Separate signed RPMs install only the selected IBM exporter and its systemd
template. They preserve administrator configuration, require explicit service
startup and do not bundle IBM MQ libraries. A public hosted yum repository is
not yet available.
