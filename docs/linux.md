# Install on Linux

The Bash installer installs a precompiled exporter and a systemd service. It
supports RHEL 8.10 and RHEL 9.x on x86-64 as provisional targets.

## Before you install

Check [compatibility](compatibility.md). You need IBM MQ 9.3.0.27, an existing
dedicated non-root service account with MQ permissions, Bash, systemd,
coreutils, tar, gzip and util-linux (`flock`, `runuser`). Online downloads also
need curl. The installer does not install packages or grant MQ permissions.

Download `install.sh` from a reviewed repository revision, or extract it from a
release archive after verifying its checksum. Do not pipe a network response
into a root shell. Use an explicit version from
[GitHub Releases](https://github.com/rknightion/mq-exporter-dist/releases).

## Install Prometheus

For an existing local queue manager `QM1` and service account `mqmon`:

```bash
sudo bash install.sh --version v0.1.0-rc.1 \
  --instance qm1 --qmgr QM1 --service-user mqmon --port 9157
```

The default MQ installation is `/opt/mqm`. Use `--mq-path` for a different
installation. The exporter lives under `/opt/mq-exporter/qm1`; `--root`
changes the parent directory. Quote paths containing spaces.

Check the service and MQ connection:

```bash
systemctl status mq-exporter-qm1.service
journalctl -u mq-exporter-qm1.service
/opt/mq-exporter/qm1/mq-dist health --qmgr QM1 --url http://127.0.0.1:9157/metrics
```

Expect `connected:true,status:2` in the health result. Check the intended queue
names separately. The [Prometheus guide](prometheus.md) explains scraping and
connection states. For OTLP delivery, use the separate [OpenTelemetry package](otel.md).

## Install offline

Transfer the archive, its `SHA256SUMS` file and installer through your approved
channel. The checksum file must come from a trusted source.

```bash
sudo bash install.sh --version v0.1.0-rc.1 \
  --archive /media/mq-exporter-dist-v0.1.0-rc.1-linux-amd64.tar.gz \
  --checksums /media/SHA256SUMS \
  --instance qm1 --qmgr QM1 --service-user mqmon --port 9157
```

The installer verifies the expected release and platform entry before extraction.
Offline installation requires no GitHub token, Go module access or container runtime.

## Connect to remote MQ

Add explicit client connection options to the installation command:

```bash
--mode client --channel APP.SVRCONN --conn-name 'mq.example.com(1414)'
```

An existing CCDT can instead be supplied with `--mode client --ccdt URL`.
Client mode still requires MQ native libraries. Local bindings mode requires the
server installation that owns the local queue manager.

## Multiple instances and updates

Use a separate instance and port for each Prometheus exporter, for example
`--instance qm2 --qmgr QM2 --port 9158`. Each instance has its own configuration,
binaries, systemd unit and journal stream. Do not reuse service names or ports
across different installation roots.

To update, run the installer with the new version and the same instance identity.
Existing configuration is preserved and binaries are backed up. `--replace-config`
explicitly replaces configuration; changing connection identity also needs
`--repoint`. These options do not change MQ objects or permissions.

The installer smoke-tests the staged replacement before replacing binaries. It
does not roll back every configuration or unit edit. If an update fails, read the
error and inspect the `.bak-*` files before restarting. See
[installation safety](safety.md) for backup and filesystem behaviour.
