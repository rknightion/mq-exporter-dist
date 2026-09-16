# Install on Linux

The Bash installer installs a precompiled exporter and a systemd service. It
supports RHEL 8.10 and RHEL 9.x on x86-64 as provisional targets.

RPM packaging is being validated separately. It uses the same exporter bytes,
with IBM's upstream version and a community packaging suffix; no signed RPM
repository is published yet. The archive installer remains the supported candidate
installation path. See [RPM installation](rpm.md) for the package layout.

## SELinux

Keep SELinux enforcing. The tested RHEL hosts needed no custom exporter policy.
This does not mean the exporter has a dedicated confined SELinux domain.

When SELinux is enabled, the installer requires `restorecon` from
`policycoreutils`. It restores policy-defined labels on its own installed files
and service unit before restarting the service. It does not recursively relabel
directories, change IBM MQ labels, add allow rules or disable enforcement.
Label-restoration failure stops installation before service restart.

For a custom installation path, inspect the expected and current contexts with
`matchpathcon` and `ls -Z`. Administrators should configure persistent path mappings
with `semanage fcontext` when needed, then apply them with `restorecon`. Do not use
blanket `chcon` or generated `audit2allow` rules as an installation workaround.
Review recent denials with `ausearch -m AVC,USER_AVC -ts recent`. A denial needs
investigation; Unix file permissions and systemd sandbox access are separate checks.

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

### Redistributable client data directories

An unpacked IBM client differs from a normally installed MQ runtime. It needs a
writable service-account home for its `.mqm` registry and a data directory for
client logs. The default home-based data path conflicts with `ProtectHome=true`.

For a dedicated account whose actual home is already a private directory such as
`/var/lib/mqmon`, an administrator-managed unit drop-in can provide:

```ini
[Service]
StateDirectory=mq-exporter-qm1
StateDirectoryMode=0700
Environment="MQ_OVERRIDE_DATA_PATH=/var/lib/mq-exporter-qm1"
ReadWritePaths=/var/lib/mqmon
```

Create the account's home with mode 0700 and ownership by that account. Use a
different state-directory name per instance. Reload systemd and restart the unit
after adding the drop-in. Do not move an existing account's home or disable
`ProtectHome` as an automatic installer workaround. These settings are not needed
merely because an exporter uses client mode with a normally installed MQ runtime.
See IBM's [redistributable client notes](https://www.ibm.com/docs/en/ibm-mq/9.3.x?topic=linux-redistributable-clients).

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
