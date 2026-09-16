# MQ Prometheus exporter

[IBM's upstream mq_prometheus](https://github.com/ibm-messaging/mq-metric-samples/tree/v6.0.0/cmd/mq_prometheus)
exposes MQ metrics for Prometheus scraping. This community package builds IBM's
unchanged pinned source; it is not affiliated with IBM or Grafana Labs and comes
without warranty.

Choose `mq-exporter-dist-VERSION-linux-amd64.tar.gz` or
`mq-exporter-dist-VERSION-windows-amd64.zip` from
[GitHub Releases](https://github.com/rknightion/mq-exporter-dist/releases).
These packages do not contain mq_otel. See the [installation guide](../README.md) for
online/offline installation, service prerequisites and multiple instances.

Keep `integrations/ibm-mq` as the scrape job name when using the supplied Grafana
integration dashboards. Verify the exact queue-manager status and queue coverage
separately; a running process or HTTP 200 is not proof of MQ monitoring.
`mq-dist health` applies to this exporter only.

See [compatibility](compatibility.md) and [evidence](evidence.md) before deployment.
