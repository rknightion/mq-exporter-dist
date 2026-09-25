# Custom QDEPTHHI build

The custom build is IBM's `mq_prometheus` from the same pinned upstream revision,
with one reviewed patch. It adds a per-queue gauge for the local queue's
queue-depth-high event threshold (`QDEPTHHI`). Everything else is unchanged.
It exists for teams who choose alert thresholds per queue from that attribute.

| | Upstream-native | Custom |
|---|---|---|
| Release tags | `v6.0.0`, `v6.0.0-1`, `v6.0.0-2` | `v6.0.0-custom-1`, `v6.0.0-custom-2` |
| Linux archive | `mq-exporter-dist-<tag>-linux-amd64.tar.gz` | `mq-exporter-dist-custom-<tag>-linux-amd64.tar.gz` |
| Exporter binary | `mq_prometheus` | `mq_prometheus_custom` |
| Source | IBM upstream, unchanged | IBM upstream plus `build/patches/qdepthhi.patch` |
| Platforms | Linux, Windows, RPM | Linux archive only |

The custom build is Prometheus-only. OpenTelemetry, Windows and RPM packages
remain upstream-native. Build metadata records the variant, the upstream tag
and commit, and the SHA-256 of each applied patch. The SBOM marks the patched
component with a pedigree entry.

## The metric

```text
ibmmq_queue_attribute_depth_high_limit{qmgr="QM1",queue="APP.ORDERS", ...} 80
```

- The value is `QDEPTHHI`, a percentage of the queue's `MAXDEPTH` (0 to 100),
  as shown by `DISPLAY QLOCAL(APP.ORDERS) QDEPTHHI`.
- Labels match `ibmmq_queue_attribute_max_depth`, including `qmgr` and `queue`.
- A value of `0` is a real setting and is exported. A queue whose definition
  returned no `QDEPTHHI` gets no sample, never a placeholder zero.
- Only local queues matched by the exporter's queue patterns are covered. Queue
  attributes are read during queue discovery, so wildcard patterns (the installer
  default) are required. Explicitly listed queue names without wildcards are
  not discovered and do not get this metric.
- Changes to `QDEPTHHI`, and new or deleted queues, appear after the next
  rediscovery (`global.rediscoverInterval`, default `1h`). Lower it in the
  instance's `config.json` if you need faster pickup.

The upstream-native build never emits this metric. Dashboards and alerts that do
not use it work unchanged on either build.

## Install

Add `--custom` to the Linux installer command. Without `--version`, it downloads
the newest published custom release:

```bash
sudo bash install.sh --custom \
  --instance qm1 --qmgr QM1 --service-user mqmon --port 9157
```

To pin a release, pass `--version v6.0.0-custom-1` instead of, or as well as,
`--custom`. The version determines the variant, and a conflicting `--custom` or
`--native` is refused. Offline installation always needs an explicit version. To switch an existing instance between variants,
add `--change-variant`. The installer keeps the other variant's binary in place
and points the service at the new one. Configuration and identity are preserved
as for any update.

## Keep the metric through scrape filtering

If your scrape job keeps an allowlist of metric names, add the new gauge. For
Grafana Alloy:

```alloy
prometheus.relabel "ibm_mq_keep" {
  forward_to = [prometheus.remote_write.metrics.receiver]
  rule {
    source_labels = ["__name__"]
    regex         = "ibmmq_qmgr_status|ibmmq_queue_depth|ibmmq_queue_oldest_message_age|ibmmq_queue_attribute_max_depth|ibmmq_queue_attribute_depth_high_limit"
    action        = "keep"
  }
}
```

For Prometheus, use the same regex in `metric_relabel_configs` with `action: keep`.

## Use it in alert rules

The gauge shares `qmgr` and `queue` with the other queue series, so it can be
joined on those labels. Comparison operators bind more tightly than `and`, so
keep each comparison in parentheses. These synthetic examples show the pattern. Choose your
own thresholds.

Queues above their own depth-high threshold:

```promql
100 * ibmmq_queue_depth / on(qmgr, queue) ibmmq_queue_attribute_max_depth
  > on(qmgr, queue) ibmmq_queue_attribute_depth_high_limit
```

Select a message-age policy per queue from its `QDEPTHHI` setting, for example
to treat queues configured with a low threshold as latency-sensitive:

```promql
(ibmmq_queue_oldest_message_age > 300)
  and on(qmgr, queue) (ibmmq_queue_attribute_depth_high_limit <= 50)
```

```promql
(ibmmq_queue_oldest_message_age > 1800)
  and on(qmgr, queue) (ibmmq_queue_attribute_depth_high_limit > 50)
```

Keep any mapping from queues or threshold bands to alert policy in your own
monitoring configuration. This repository deliberately ships no environment-specific
mapping.

## Update

Custom and native instances update independently; see
[updating multiple instances](linux.md#update-all-instances-on-a-host).
