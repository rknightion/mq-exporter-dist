# RPM installation

Separate `mq-prometheus` and `mq-otel` RPM candidates wrap the tested Linux archive
binaries. There is no signed RPM repository yet. Native RPM install, upgrade,
removal and SELinux lifecycle acceptance are still required before release.
Use the [archive installer](linux.md) for the current release candidates.

## Versions and ownership

RPM `Version` follows IBM's upstream tag. `Release` identifies this distribution:
`6.0.0-0.1.0~rc.5.mqdist` packages upstream 6.0.0 from distribution v0.1.0-rc.5.
The stable form is `6.0.0-0.1.0.mqdist`; RPM sorts the candidate below it.
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

For a future signed Prometheus RPM, configure before enabling the service:

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
