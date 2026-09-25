# Install on Linux

The Bash installer installs a precompiled exporter and a systemd service. It
supports RHEL 8.10 and RHEL 9.x on x86-64 as provisional targets.

Signed RPMs use the same exporter bytes, with IBM's upstream version and a
community packaging suffix. No hosted yum repository is published yet. See
[RPM installation](rpm.md) for verification, installation and package layout.

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
into a root shell.

Without `--version`, the installer downloads the newest published release: the
upstream-native build by default, or the [custom QDEPTHHI build](custom.md) with
`--custom`. Pin a version from
[GitHub Releases](https://github.com/rknightion/mq-exporter-dist/releases) for
repeatable installs.

## Install Prometheus

For an existing local queue manager `QM1` and service account `mqmon`:

```bash
sudo bash install.sh --version v6.0.0-1 \
  --instance qm1 --qmgr QM1 --service-user mqmon --port 9157
```

`--instance` is a label you choose for this installed service. It is not an IBM MQ
identifier to look up. Use a lowercase label containing letters, digits and hyphens,
starting with a letter and no longer than 40 characters, such as `qm1`. The queue
manager's actual name belongs in `--qmgr`.

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
sudo bash install.sh --version v6.0.0 \
  --archive /media/mq-exporter-dist-v6.0.0-linux-amd64.tar.gz \
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

To update one instance, run the installer with the new version and the same
instance identity. Existing configuration is preserved and binaries are backed up.
`--replace-config` explicitly replaces configuration; changing connection identity
also needs `--repoint`. These options do not change MQ objects or permissions.
The installer refuses an older version of the same track unless you add
`--allow-downgrade`, and refuses to switch between the native and
[custom](custom.md) builds unless you add `--change-variant`.

Each instance records its installed release in `release` and its build variant in
`variant`. Instances installed before `v6.0.0-1` have neither file and are treated
as native builds.

## Update all instances on a host

`update.sh`, included in every Linux archive, finds the instances this installer
manages and updates them one at a time. On an online host, one command updates
every instance to the newest published release of its own track:

```bash
sudo bash update.sh --dry-run   # review the plan
sudo bash update.sh             # apply it
```

`--native` or `--custom` limits a run to one track. Pin exact versions with
`--native-version v6.0.0-2` and `--custom-version v6.0.0-custom-2`; do that for
change-controlled rollouts so every host gets the same release. Use the `update.sh`
from the newest archive you are installing.

1. Review the plan. A dry run changes nothing:

   ```bash
   sudo bash update.sh --dry-run
   ```

   The updater finds instances from their systemd units, including alternate
   `--root` directories. It lists each instance's root, port, exporter, variant,
   current version and target, and the action it will take. Add `--root DIR` to
   also report instance directories under another root that have no matching unit.

2. Read the `UNMANAGED` lines. They list exporter copies the updater will not
   touch: RPM installations, units or drop-ins it did not create, and running
   exporter processes outside the managed layout. Each line shows the binary path,
   version if known, listening port, and the reason. Update those copies with
   the tool that installed them.

3. Run the update without `--dry-run`. Offline hosts pass explicit versions, and
   the archives and checksum files:

   ```bash
   sudo bash update.sh --native-version v6.0.0-2 --custom-version v6.0.0-custom-2 \
     --native-archive mq-exporter-dist-v6.0.0-2-linux-amd64.tar.gz --native-checksums native/SHA256SUMS \
     --otel-archive mq-otel-dist-v6.0.0-2-linux-amd64.tar.gz --otel-checksums native/SHA256SUMS \
     --custom-archive mq-exporter-dist-custom-v6.0.0-custom-2-linux-amd64.tar.gz --custom-checksums custom/SHA256SUMS
   ```

   Native and custom releases have separate `SHA256SUMS` files. The OTel archive
   is needed only if the host has OTel instances.

Each instance keeps its variant: native Prometheus and OTel instances follow
`--native-version`, and custom instances follow `--custom-version`. The updater
does not change configuration, identity, ports, enablement or whether a service
is running. It skips instances already at the target version, refuses downgrades
unless given `--allow-downgrade`, and skips a Prometheus instance that is not
connected to MQ before the update unless given `--include-unhealthy`. That way an
existing outage is not mistaken for a failed update.

Before changing anything, the updater runs the installer's full preflight for
every target, including ownership and permission checks and the upstream
configuration reader. If any preflight fails, it stops with no changes.

For each instance in turn, it:

- snapshots the instance's files and unit into `<root>/.update-backups/<instance>.<random>/`,
  with a manifest of each file's hash, owner, mode and SELinux context;
- installs the new binaries without starting them, then restarts the service only
  if it was running;
- checks that a new process runs the new file and stays up, and that a Prometheus
  instance reconnects to its queue manager (`--verify health`, the default).
  `--verify active` checks only the service. For custom instances with queue
  series, it also checks that the QDEPTHHI gauge is present.

If an instance fails, the updater restores it from its snapshot and stops. It
removes files the update created, restores owners, modes and SELinux contexts,
and restores enablement and running state. It does not continue to the remaining
instances.

| Exit | Meaning |
|---|---|
| 0 | Every targeted instance was updated and verified, or nothing needed updating |
| 1 | Nothing was changed (argument, archive or preflight failure) |
| 2 | Partial: earlier instances were updated, one failed and was rolled back, and later ones were not attempted |
| 3 | A rollback failed; restore that instance manually |

The final table reports each instance as `updated`, `rolled-back`,
`ROLLBACK-FAILED`, `not-attempted` or `skip-*`. A signal (Ctrl-C, SIGTERM or a
dropped SSH session) rolls back the instance in progress before exiting. Run
long updates in `tmux` or `screen` anyway.

### Recovery

Rerunning the same command is safe: updated instances show `skip-current`.
If an instance reports `ROLLBACK-FAILED`, stop its service and restore it from
the snapshot directory named in the report:

- `manifest` lists each file by number and path, and whether it existed before the update. For each file that existed, it also records the file's SHA-256, owner, mode and SELinux context.
- `files/<number>` is the pre-update copy of each file that existed.
- `created/` holds files the update added, already moved out of the way.
- `journal` and `install.log` record what happened.

Copy each `files/<number>` back to its path, apply the recorded owner and mode
with `chown` and `chmod`, then run `restorecon` on those paths. Run
`systemctl daemon-reload`, then restart the service and check it with `mq-dist health`.
Snapshots are never deleted automatically. Remove old ones once you no longer need them.

The installer smoke-tests the staged replacement before replacing binaries.
See [installation safety](safety.md) for backup and filesystem behaviour.
