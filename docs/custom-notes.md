Custom build of IBM's mq_prometheus v6.0.0 for Linux x86-64. It is the upstream-native
exporter plus one reviewed patch, `build/patches/qdepthhi.patch`, which adds the
per-queue gauge `ibmmq_queue_attribute_depth_high_limit`: the local queue's
QDEPTHHI setting, as a percentage of MAXDEPTH. It is not an official IBM release or
an IBM-supported product. It is not affiliated with IBM or Grafana Labs and is
provided without warranty.

The archive uses the `mq-exporter-dist-custom-` prefix and contains the
`mq_prometheus_custom` binary, the Linux installer and multi-instance updater,
notices, SBOM and build metadata. The metadata and SBOM record the upstream tag and
commit and the patch's SHA-256. IBM MQ SDK/runtime libraries are not included.
There are no Windows, OpenTelemetry or RPM packages on this track; use the native
releases for those.

Custom tags (`vX.Y.Z-custom-N`) have their own counter, separate from native
releases (`vX.Y.Z-N`). The custom release is never marked as the repository's
latest release. See the
[custom build guide](https://rknightion.github.io/mq-exporter-dist/custom/) and the
[compatibility guide](https://rknightion.github.io/mq-exporter-dist/compatibility/)
for what was validated.
