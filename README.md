# mq-exporter-dist

Community packaging and installation for [IBM's MQ Prometheus exporter](https://github.com/ibm-messaging/mq-metric-samples/tree/v6.0.0/cmd/mq_prometheus).
This is not an IBM-supported product or an official IBM release. The collector is
IBM's unchanged source. Distribution versions are independent of upstream versions.

Release publication is currently gated on independent IBM SDK signature/checksum
verification. The candidate workflow can still produce versioned evaluation
archives; the [maintainer guide](docs/maintaining.md) gives the exact release gate.

**Initial platform targets are provisional:** RHEL 8.10 / glibc 2.28 and RHEL 9.x /
glibc 2.34, Linux x86-64, IBM MQ 9.3.0.27 runtime compatibility; and Windows Server
2019 amd64. The Windows MQ runtime version must be independently established.
See the [compatibility matrix](docs/compatibility.md) for measured evidence and
unavailable tests. A candidate release is not a stable compatibility claim.

## Target-server prerequisites

An existing licensed 64-bit IBM MQ installation and an existing dedicated service
account with the required MQ permissions. Binaries dynamically load IBM MQ native
libraries. MQ libraries and glibc are **not included**. Do not install a development
toolchain on the monitored server: Git, Go, GCC, SDK headers, Docker, jq, gh and Go
module registry access are not needed.

Linux installation needs Bash, systemd, GNU coreutils/tar/gzip, util-linux
(`flock`, `runuser`), and curl for online downloads. These are normally present on
RHEL; the installer does not install packages. Windows installation needs elevated
64-bit Windows PowerShell 5.1 and the installed MQ native runtime. No PowerShell 7
or C compiler is needed on Windows Server 2019.

## Linux

Download `install.sh` from a reviewed repository revision or extract it from a
verified release archive. Do not pipe a network response directly into a root shell.
Use a concrete version from [Releases](https://github.com/rknightion/mq-exporter-dist/releases):

```bash
sudo bash install.sh --version v0.1.0-rc.1 \
  --instance qm1 --qmgr QM1 --service-user mqmon --port 9157
```

For offline installation, transfer the release archive, `SHA256SUMS` and installer
through your approved channel, then supply `--archive /media/mq-exporter-dist-v0.1.0-rc.1-linux-amd64.tar.gz
--checksums /media/SHA256SUMS` in addition to the same arguments. An archive name is
not trusted: the checksum entry is selected by the explicit release and platform.

Instances have separate binaries, configuration, units and journal streams. A second
instance uses `--instance qm2 --qmgr QM2 --port 9158`. Existing configuration is
preserved. Use `--replace-config` to replace it with a backed-up generated file;
changing connection identity also requires `--repoint`. Never run concurrent
installations into different roots using the same service names or ports.

```bash
journalctl -u mq-exporter-qm1.service
/opt/mq-exporter/qm1/mq-dist health --qmgr QM1 --url http://127.0.0.1:9157/metrics
```

`Restart=on-failure` retries initial connection failures every 15 seconds. After a
successful connection, upstream `keepRunning` handles reconnection. Read logs for
authorization or configuration failures rather than treating retries as readiness.

For explicit client mode, add `--mode client --channel APP.SVRCONN
--conn-name 'mq.example.com(1414)'`, or `--mode client --ccdt <URL>` for an existing
CCDT. Local bindings uses the selected server installation and needs a real local
queue manager; a redistributable client smoke test does not prove bindings works.

## Windows

Transfer `install.ps1` and the Windows ZIP/checksums, or let the installer download
the explicit public release. Run from elevated Windows PowerShell 5.1:

```powershell
$credential = Get-Credential 'EXAMPLE\mqmon'
.\install.ps1 -Version v0.1.0-rc.1 -Instance qm1 -QueueManager QM1 `
  -ServiceAccount 'EXAMPLE\mqmon' -ServiceCredential $credential -Port 9157
```

Offline adds `-Archive 'D:\Media\mq-exporter-dist-v0.1.0-rc.1-windows-amd64.zip'
-Checksums 'D:\Media\SHA256SUMS'`. Provision the dedicated account's “Log on as a
service” right and MQ permissions separately. Passwords are not command-line
arguments. Existing service credentials are preserved during updates.

The included `mq-service.exe` implements the Windows Service Control Manager
protocol. It starts the unchanged exporter, keeps its MQ-specific PATH local to the
child, retries exits every 15 seconds and stops its tracked child on service stop.
The console exporter is never registered directly with SCM. There is no MQ SERVICE
object creation. Service logs are per-instance `logs\exporter.log`; arrange local
retention/rotation while the service is stopped. Service integration is provisional
until the Server 2019 acceptance commands have passed.

```powershell
Get-Service mq-exporter-qm1
& 'C:\Program Files\mq-exporter\qm1\mq-dist.exe' health --qmgr QM1 --url http://127.0.0.1:9157/metrics
```

## Configuration and health

Both installers use the same precompiled configuration generator. It writes UTF-8
JSON, a valid YAML representation read by IBM's YAML reader. Preserve JSON syntax
when editing managed `config.json`; free-form YAML is not supported by the managed
identity check. Examples use `QM1`, `APP.QUEUE` and `mq.example.com`.

The listener defaults to `127.0.0.1`; there is no automatic firewall or TLS change.
For a remote scraper, configure an appropriate listener and TLS deliberately.
Use a protected password file with `--user/--password-file` or `-MQUser/-PasswordFile`.
Do not store plaintext credentials in examples or source control.

A running process or HTTP 200 is not proof of monitoring. The health helper matches
exactly `ibmmq_qmgr_status` and exactly the requested `qmgr` label, accepting numeric
forms such as `2e0` but rejecting malformed, duplicate and incomplete responses.
Status `2` means connected/running; `0` reports loss of a previously established
connection. A failed first connection exits `10` before the HTTP listener starts.
Queue-series observations are reported separately and do not prove intended queue
coverage. Compare observed queue names against your intended list.

Empty-effective patterns are rejected, and exclusions such as `!SYSTEM.*` are
preserved. Upstream's non-durable subscription admission check needs `30 + 5N`
handles for N monitored queues: MAXHANDS=256 admits 45. Narrowing
`queueSubscriptionSelector` does not change that check. Durable subscriptions need
two distinct pre-existing QLOCAL reply queues as well as `durableSubPrefix`.
This project never changes MAXHANDS, creates MQ objects or changes TLS policy.

Keep `job="integrations/ibm-mq"` in the [scrape example](examples/alloy.alloy), because
the Grafana IBM MQ integration dashboards select that job name.

## Build machines and maintainers

Build machines need Git, Go, Python 3.12+, just, shellcheck and PowerShell for checks;
Linux builds additionally need Docker. Windows builds acquire a pinned GCC/binutils
toolchain. IBM's SDK/client inputs are downloaded from IBM, checksum-pinned and
kept in ignored build storage. Maintainers must have rights to use those inputs;
their license is separate from this project's Apache-2.0 license.

```bash
just check
just build-linux v0.1.0-rc.1
# On a Windows build host:
just build-windows v0.1.0-rc.1
just release-index
just public-check
```

The build uses upstream `v6.0.0`, commit
`7bce9b8ef9ef513ff77688f022929843d5ba7eaf`, vendored mq-golang v5.7.2,
`-mod=vendor`, `GOTOOLCHAIN=local`, and disabled module network access. See
[maintenance](docs/maintaining.md), [installation safety](docs/safety.md), and
[build input pins](build/inputs.json). SDK and toolchain inputs never enter release
archives. Archives include notices, an SBOM and build evidence. GitHub release
automation attests and publishes the tested bytes without rebuilding them.
