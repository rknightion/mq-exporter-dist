# Prometheus

[IBM's mq_prometheus](https://github.com/ibm-messaging/mq-metric-samples/tree/v6.0.0/cmd/mq_prometheus)
exposes MQ metrics on an HTTP endpoint for Prometheus or Grafana Alloy to scrape.

Download the `mq-exporter-dist` archive for your platform from
[GitHub Releases](https://github.com/rknightion/mq-exporter-dist/releases).
The package contains no OpenTelemetry exporter or MQ runtime.

## Install

Follow the [Linux guide](linux.md) or [Windows guide](windows.md).
Both guides use Prometheus as their default exporter and configure a listener on
`127.0.0.1:9157`. Give each queue manager a separate instance and port.

## Verify the connection

On Linux:

```bash
/opt/mq-exporter/qm1/mq-dist health --qmgr QM1 --url http://127.0.0.1:9157/metrics
```

On Windows:

```powershell
& 'C:\Program Files\mq-exporter\qm1\mq-dist.exe' health --qmgr QM1 --url http://127.0.0.1:9157/metrics
```

Expect `connected:true` and `status:2`. The helper checks the exact
`ibmmq_qmgr_status` metric and the exact `qmgr="QM1"` label. It rejects failed
HTTP requests, partial responses, malformed samples and duplicate status samples.

A running process or HTTP 200 does not prove that MQ monitoring works. Check
queue metrics separately: compare the queue names received by your monitoring
system with the queues you intended to monitor.

## Connect your monitoring system

Keep `integrations/ibm-mq` as the scrape job name if you use the Grafana IBM MQ
integration dashboards. Their queries select that job name.

```yaml
scrape_configs:
  - job_name: integrations/ibm-mq
    static_configs:
      - targets: ['127.0.0.1:9157']
```

This address works when the scraper runs on the same host. For a remote scraper,
configure the listener, network access and TLS deliberately. The installer does
not open firewall ports or configure TLS. An
[Alloy example](https://github.com/rknightion/mq-exporter-dist/blob/main/examples/alloy.alloy)
is also available.

## Connection failures

If the first MQ connection fails, the exporter exits `10` before opening its HTTP
listener. The service retries after 15 seconds. After a successful connection,
`keepRunning` keeps the listener available during a disconnection; status can
then be `0`. Check [troubleshooting](troubleshooting.md) if status does not return
to `2`.
