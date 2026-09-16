# MQ OpenTelemetry exporter

[IBM's upstream mq_otel](https://github.com/ibm-messaging/mq-metric-samples/tree/v6.0.0/cmd/mq_otel)
pushes MQ metrics over OTLP. This community package uses the same pinned IBM tag
and vendored dependencies as the Prometheus package, without changing its
collector. It is not affiliated with IBM or Grafana Labs and comes without warranty.

**Not yet published.** OpenTelemetry packages are not included in v0.1.0-rc.1.
Use this guide when an OTel candidate appears in
[GitHub Releases](https://github.com/rknightion/mq-exporter-dist/releases).
Do not use the Prometheus archive as an OTel package. Check
[compatibility](compatibility.md) before deployment.

## Separate downloads

- Linux: `mq-otel-dist-VERSION-linux-amd64.tar.gz`
- Windows: `mq-otel-dist-VERSION-windows-amd64.zip`

Each package contains mq_otel only, plus its actual upstream configuration reader,
installer, diagnostics, notices and metadata. No Prometheus binary or IBM MQ runtime
is bundled. Target machines need no compiler, SDK headers or module registry access.

## Installation

Use a distinct instance name, for example `qm1-otel`. The shipped installer defaults
to OTel; the shared repository installer requires `--exporter otel` or
`-Exporter otel`. Choose the version matching your archive and trusted checksum
file. For example, after a candidate containing OTel is available:

```bash
sudo bash install.sh --exporter otel --version "$VERSION" \
  --archive "$ARCHIVE" --checksums SHA256SUMS \
  --instance qm1-otel --qmgr QM1 --service-user mqmon \
  --otlp-endpoint https://otel.example.com:4318
```

Windows PowerShell 5.1, elevated, with a dedicated account already granted Log on
as a service and MQ permissions:

```powershell
$credential = Get-Credential '.\mqmon'
.\install.ps1 -Exporter otel -Version $Version -Archive $Archive -Checksums .\SHA256SUMS `
  -Instance qm1-otel -QueueManager QM1 -ServiceAccount '.\mqmon' `
  -ServiceCredential $credential -OTLPEndpoint 'https://otel.example.com:4318'
```

Omit archive/checksum arguments for a versioned online download. Client connection
options, private MQ password files, offline verification, backups and configuration
preservation follow the [Linux](linux.md) and [Windows](windows.md) guides. Existing instances cannot
silently switch exporter or destination; use a new instance or explicit repoint and
configuration replacement. OTel has no listener port; `Port` is unused.

## Receiver and TLS

An `https://` URL selects OTLP/HTTP. A `host:port`, such as `otel.example.com:4317`,
selects OTLP/gRPC with TLS by default. Plaintext requires explicit
`--otlp-insecure` / `-OTLPInsecure`; use it only for an intentionally unencrypted
local receiver. This option disables transport TLS, not just certificate checks.
Do not put credentials in endpoint URLs.

The installer configures no cloud account or receiver credentials. Prefer a local
OTel Collector for authentication and forwarding. On Linux, upstream
environment-based TLS/headers can be supplied through a private systemd
`EnvironmentFile` in an administrator-managed drop-in. Do not put secrets in unit
command lines or global PATH. Check certificate/key access under the service's
actual identity. The Windows SCM adapter deliberately forwards only its small OS
environment allowlist, not OTEL variables: custom OTLP headers and client
certificates are not supported through that adapter yet. Use system-trusted TLS
without additional authentication, or an explicitly configured local receiver
which handles authenticated forwarding.

## Validation and behavior

The matching `mq-config-check` validates through mq_otel's own upstream reader.
It proves configuration parsing, not delivery. **There is no Prometheus HTTP
listener and `mq-dist health` does not apply.** At the receiver, verify fresh
`ibmmq.*` metrics, the exact queue-manager attributes, expected queue names and
collection timestamps. Verify MQ connection and queue coverage separately.

The pinned source exits nonzero when the initial MQ connection fails (normally
exit 1, not Prometheus's exit 10). systemd and the SCM adapter retry failed starts
after 15 seconds. With the MQ 9.3.0.35 trial server, live tests verified actual
OTLP/HTTP queue metrics and recovery through the service restart policy after an
established MQ connection was lost. This is process restart, not an in-process
reconnection guarantee. See [compatibility](compatibility.md) for runtime versions
and untested transports.

OTel distinguishes counters and gauges. Metric names and types may be transformed
by your receiver, so existing Prometheus dashboards are not automatically compatible.
The upstream `overrideCType` option defaults to false here. The Prometheus scrape
job name `integrations/ibm-mq` is not an OTLP delivery setting.
