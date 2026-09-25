# MQ exporters

> [!WARNING]
> Community-contributed software, provided **AS IS, without warranty of any kind**.
> This project is not affiliated with, endorsed by, sponsored by or supported by
> IBM or Grafana Labs.

Precompiled packages and installers for [IBM's MQ exporters](https://github.com/ibm-messaging/mq-metric-samples).
Install one exporter on a server with an existing IBM MQ runtime. You do not need
Go, Git, a compiler, MQ SDK headers or access to Go module registries on that server.

## Choose your exporter

| | Prometheus | OpenTelemetry |
|---|---|---|
| Collector | `mq_prometheus` | `mq_otel` |
| Delivery | Prometheus scrapes an HTTP endpoint | Sends metrics to an OTLP receiver |
| Package prefix | `mq-exporter-dist` | `mq-otel-dist` |
| Get started | [Prometheus guide](docs/prometheus.md) | [OpenTelemetry guide](docs/otel.md) |

Each download contains one exporter and its installation tools. You do not need
both packages. Both use unchanged IBM upstream source at `v6.0.0`; distribution
versions are separate from IBM's exporter version. The optional
[custom build](docs/custom.md) adds one reviewed patch on a separate release track.

## Install

**Platform support remains provisional.** Current releases are
[v6.0.0-1](https://github.com/rknightion/mq-exporter-dist/releases/tag/v6.0.0-1), with
separate Prometheus and OpenTelemetry packages for Linux and Windows, and
[v6.0.0-custom-1](https://github.com/rknightion/mq-exporter-dist/releases/tag/v6.0.0-custom-1),
a Linux Prometheus build that adds a per-queue [QDEPTHHI gauge](docs/custom.md).
Signed v6.0.0 RPMs remain current.

1. Check the [platform requirements](docs/compatibility.md) and your installed MQ runtime.
2. Follow the [Linux installation guide](docs/linux.md) or [Windows installation guide](docs/windows.md).
3. Check the MQ connection and expected queues using your [exporter's guide](docs/prometheus.md).

Installers support online and offline installation. They preserve existing
configuration by default and do not create MQ objects or change MQ permissions,
MAXHANDS, firewall rules or TLS policy. On Linux, `update.sh` updates every
managed instance on a host in one run, with a snapshot and automatic rollback
per instance.

## Requirements

Initial targets are Linux x86-64 on RHEL 8.10 / glibc 2.28 and RHEL 9.x /
glibc 2.34, with IBM MQ 9.3.0.27; and Windows Server 2019 amd64.
Live MQ 9.3.0.35 lifecycle checks passed in the disposable lab; exact 9.3.0.27
server local-bindings acceptance remains outstanding. See the compatibility matrix.

Target servers need an existing licensed 64-bit IBM MQ installation and a
dedicated service account with the required MQ permissions. The executables
dynamically load IBM MQ libraries. MQ libraries and glibc are not bundled.

Build machines have different requirements: Git, Go, Python 3.12+, just,
shellcheck and PowerShell, plus Docker for Linux builds. Windows builds acquire
a pinned C toolchain. These are **build-machine requirements only**.
Source pins and build commands are in the repository's
[maintainer guide](https://github.com/rknightion/mq-exporter-dist/blob/main/docs/maintaining.md).

[Read the documentation](https://rknightion.github.io/mq-exporter-dist/) ·
[Download releases](https://github.com/rknightion/mq-exporter-dist/releases) ·
[Report a vulnerability](SECURITY.md)
