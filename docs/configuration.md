# Configure an exporter

Both installers generate UTF-8 JSON that IBM's YAML reader accepts. Keep JSON
syntax when editing managed `config.json`; the instance identity check does not
accept free-form YAML.

## Queue selection

Use `--queues 'APP.*,!SYSTEM.*'` on Linux or `-Queues 'APP.*,!SYSTEM.*'` on Windows.
Quote exclusions so the shell preserves the leading `!`. Empty-effective queue
patterns are rejected. Check the resulting queue names in your monitoring system;
a healthy MQ connection does not establish queue coverage.

The upstream non-durable subscription admission calculation is `30 + 5N` handles
for N monitored queues. `MAXHANDS=256` admits 45 queues under that check. Narrowing
`queueSubscriptionSelector` does not reduce the calculation. Durable subscriptions
require two distinct pre-existing QLOCAL reply queues as well as `durableSubPrefix`.
The installer does not change MAXHANDS or create MQ objects.

## Authentication and private files

Use `--user` and `--password-file` on Linux, or `-MQUser` and `-PasswordFile` on
Windows. Keep password files and CCDTs in protected locations readable by the
service account. Never place credentials in source control or command lines.

On Linux, `ProtectHome=true` prevents service access to home directories even when
Unix file permissions permit reading. Use a protected configuration directory
outside home and temporary directories. Local bindings mode uses shared host IPC;
do not enable `PrivateTmp` without validating MQ access.

On Windows, the installation ACL gives the service account read/execute access to
binaries and configuration, and write access to its logs. Use the service identity
when checking access to external credentials or certificate files.

## Listener and receiver

Prometheus listens on `127.0.0.1` by default. Set the listener and TLS deliberately
for a remote scraper; the installer changes neither firewall rules nor TLS policy.
Each Prometheus instance needs a port from 1 to 65535.

OpenTelemetry has no listener port. Configure its destination with
`--otlp-endpoint` or `-OTLPEndpoint`. Read the [OTel guide](otel.md) for protocol,
TLS and authentication limits.

## Preserve or replace configuration

Updates preserve existing configuration. Use `--replace-config` / `-ReplaceConfig`
only when you intend to regenerate it. Changing exporter, queue manager or
connection identity also requires `--repoint` / `-Repoint`; a separate instance
is often clearer when you need both configurations.

The matching `mq-config-check` checks the file through the selected exporter's
upstream reader before installation. Successful parsing does not prove MQ access
or metrics delivery.
