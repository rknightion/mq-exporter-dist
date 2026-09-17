# RPM installation

Separate `mq-prometheus` and `mq-otel` RPMs wrap the tested Linux archive
binaries. Package and repository-metadata signatures use the dedicated project
key. There is no public hosted yum repository yet. See the
[compatibility limits](compatibility.md) before deploying an RPM.

Download the two RPMs, `RPM-GPG-KEY-mq-exporter-dist`, `RPM-SHA256SUMS` and
`RPM-SHA256SUMS.asc` from the
[v6.0.0 release](https://github.com/rknightion/mq-exporter-dist/releases/tag/v6.0.0).
The signing-key fingerprint is
`A3D2 D5D6 8404 A4E6 088E 3B2E B031 8897 DDF2 F968`. Verify that fingerprint
through a separate trusted copy of this documentation before importing the key.

```bash
gpg --show-keys --fingerprint RPM-GPG-KEY-mq-exporter-dist
gpg --import RPM-GPG-KEY-mq-exporter-dist
gpg --verify RPM-SHA256SUMS.asc RPM-SHA256SUMS
sha256sum -c --ignore-missing RPM-SHA256SUMS
sudo rpm --import RPM-GPG-KEY-mq-exporter-dist
rpm --checksig mq-prometheus-6.0.0-6.0.0.mqdist.x86_64.rpm
sudo dnf install ./mq-prometheus-6.0.0-6.0.0.mqdist.x86_64.rpm
```

Use the `mq-otel` filename instead to install only the OpenTelemetry exporter.
Neither RPM installs or changes Prometheus, Alloy or an OTLP receiver.

## Versions and ownership

RPM `Version` follows IBM's upstream tag. `Release` identifies this distribution:
`6.0.0-6.0.0~rc.1.mqdist` packages upstream 6.0.0 from distribution v6.0.0-rc.1.
The stable form is `6.0.0-6.0.0.mqdist`; RPM sorts the candidate below it.
Release numbering follows the exporter source, not the IBM MQ runtime version.
These are community packages, not IBM RPMs.

Each product owns its binaries under `/usr/libexec/mq-prometheus` or
`/usr/libexec/mq-otel`, and its corresponding systemd template under
`/usr/lib/systemd/system`. RPM does not own or overwrite administrator-created
instance JSON, account credentials or unit drop-ins. It does not automatically
start, enable or restart instances during installation or upgrades.

Do not point the Bash installer at RPM-owned directories. Migration from an
archive installation is explicit: preserve its configuration, prepare a separate
RPM instance, then stop the old instance before starting the replacement on the
same port. Do not run two collectors accidentally against the same instance.

## Configure an instance

The existing IBM MQ 9.3.0.27 runtime, a dedicated `mqmon` account and appropriate
MQ permissions remain prerequisites. RPM does not install IBM software, create
MQ objects, grant access or alter the firewall. No compiler is required.

For the Prometheus exporter RPM, configure before enabling the service:

```bash
umask 077
stage=$(mktemp)
/usr/libexec/mq-prometheus/mq-dist config --qmgr QM1 --port 9157 \
  --queues 'APP.*,!SYSTEM.*,!AMQ.*' > "$stage"
# For a NEW instance only; preserve an existing configuration during upgrades.
test ! -e /etc/mq-prometheus/qm1.json
install -o mqmon -g mqmon -m 0600 "$stage" /etc/mq-prometheus/qm1.json
restorecon /etc/mq-prometheus/qm1.json
runuser -u mqmon -- env LD_LIBRARY_PATH=/opt/mqm/lib64:/usr/lib64:/lib64 \
  /usr/libexec/mq-prometheus/mq-config-check -f /etc/mq-prometheus/qm1.json
systemctl enable --now mq-prometheus@qm1.service
```

Run configuration steps in a shell that stops on failure (`set -e`). Remove only
the temporary file you created after retaining the installed configuration.
Verify exact MQ connection status and queue coverage, not just service state.
For OTel use `mq-otel`, `--exporter otel` and your `--otlp-endpoint`; validate
fresh queue metrics at that receiver instead of scraping an HTTP listener.

Create separate JSON files and ports for additional queue managers. Use
`systemctl edit mq-prometheus@qm1.service` for another account or MQ library path.
Keep passwords out of unit files and use restricted password files. Redistributable
clients also need the [private data/home setup](linux.md#redistributable-client-data-directories).

## SELinux and updates

Standard vendor paths use the host's SELinux file-context policy. RPM applies
labels during transactions; package scriptlets restore labels only on package-owned
paths. No custom SELinux policy, port labelling or permissive domain is installed.
Administrator-created configuration needs its own correct label and permissions.
See [SELinux troubleshooting](linux.md#selinux).

Upgrade during a maintenance window and explicitly restart each configured
instance afterwards. Removing a package stops/disables its instances but leaves
administrator-created configuration in place. It does not touch archive-managed
`mq-exporter-*` services or the other exporter product.

Alloy and Prometheus configuration remain separate examples, never RPM payload
or installer-managed state. See [monitoring configuration](prometheus.md#connect-your-monitoring-system).
