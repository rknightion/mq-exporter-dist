Community distribution candidate of IBM's unchanged mq_prometheus and mq_otel
v6.0.0, delivered as separate packages. Install only the exporter you need.
This is not an official IBM release or an IBM-supported product. It is not
affiliated with IBM or Grafana Labs and is provided without warranty.

Prometheus archives use the `mq-exporter-dist-` prefix; OpenTelemetry archives use
`mq-otel-dist-`. Each has a Linux tar.gz and Windows ZIP, with its own configuration
reader. OTel requires an explicitly configured OTLP receiver and does not expose
the Prometheus health endpoint. The earlier published v0.1.0-rc.1 contains
Prometheus only; these notes describe the next candidate's scope.

Initial targets: Linux x86-64 on RHEL 8.10 / glibc 2.28 and RHEL 9.x / glibc 2.34,
with an existing IBM MQ 9.3.0.27 runtime; Windows Server 2019 amd64, with its MQ
runtime version independently confirmed. Platform support remains provisional.

Archives contain precompiled executables, installers, notices, SBOM and build
metadata. IBM MQ SDK/runtime libraries are not included. SHA256SUMS and GitHub
provenance cover these exact candidate bytes. Review the compatibility matrix and
per-artifact metadata before use. Native RHEL and Server 2019 lifecycle checks
are described in [compatibility](compatibility.md); live MQ and local-bindings
acceptance remain outstanding. Build metadata records build-time checks, not
subsequent native validation.

The rc.4 Windows installer fixes ACL inspection on Server 2019 by reading SIDs
directly, without weakening write-permission checks. Older installer copies can
fail when Windows cannot translate application-package SIDs to account names.
