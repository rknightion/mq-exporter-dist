---
id: MQ-1
title: Add a QDEPTHHI exporter variant and safe multi-instance updater
status: In Progress
assignee:
  - '@claude'
created_date: '2026-09-25 09:18'
updated_date: '2026-09-25 10:00'
labels: []
dependencies: []
references:
  - build/inputs.json
  - install/install.sh
  - docs/compatibility.md
type: feature
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The distribution currently builds IBM's pinned mq_prometheus unchanged (v6.0.0, commit 7bce9b8ef9ef513ff77688f022929843d5ba7eaf). It does not expose the local-queue QDEPTHHI attribute needed for queue-specific monitoring. Produce two clearly identified Prometheus exporter binaries from the same pinned upstream revision: the unchanged upstream-native build and an explicitly patched build that exports QDEPTHHI per local queue. Preserve the existing OTel distribution path.

The Linux installer currently installs one mq_prometheus per instance, normally under /opt/mq-exporter/<instance>; one host may run several queue managers on distinct ports and may have instances under an alternate --root. Extend packaging/installation so the intended variant is explicit, then provide a safe update command for all managed instances on a host. Do not include customer names, hosts, queue-policy mappings or credentials in this public repository.

Recreate the disposable AWS IBM MQ lab for end-to-end validation. Compare MQSC DISPLAY QLOCAL(*) QDEPTHHI with each patched exporter's raw /metrics response and verify the metric survives installation and an upgrade of multiple simultaneous instances. A successful build or /metrics HTTP 200 alone is insufficient. Record the lab setup, tested MQ and OS versions, commands, results and teardown. If prior lab infrastructure is unavailable, reconstruct it and document the reproducible procedure before claiming live validation.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The build produces separately named upstream-native and QDEPTHHI-enhanced Prometheus binaries from the same pinned upstream revision, with variant and source/patch provenance in release metadata and checksums; existing OTel artifacts continue to build. The native binary remains free of the custom metric.
- [ ] #2 The enhanced exporter emits a documented, stable QDEPTHHI gauge with queue-manager and queue identity for each eligible local queue. It distinguishes an unavailable attribute from a legitimate zero, handles queue discovery/attribute changes, and has focused regression tests for parsing and emission.
- [ ] #3 Archives and installer expose an explicit variant choice without silently changing existing installs. Version/checksum verification, service-account permissions, config preservation and current install/rollback behavior remain intact. Update repo policy and user docs to describe both variants and their upstream relationship.
- [ ] #4 A Linux update command inventories all managed exporter instances, including separate ports and supported alternate roots, and reports current and target versions/variants before changes. Dry-run is available. Discovery uses managed instance identity/service metadata and never blindly overwrites arbitrary same-named binaries.
- [ ] #5 The updater preflights all target instances, updates them serially with staged verified binaries and per-instance backups, preserves each config, identity, port and service definition, and coordinates stop/start or restart deliberately. It verifies each instance after replacement, rolls back a failed instance and reports partial success accurately. Untrusted paths and symlinks cannot redirect writes.
- [ ] #6 Automated tests cover multiple installed instances, mixed starting versions/variants, alternate roots, dry-run, preflight failure, successful update and rollback without losing configuration; installer/updater documentation includes an operator procedure and recovery steps.
- [ ] #7 A recreated AWS lab runs real IBM MQ with at least two simultaneous exporter instances on different ports. MQSC QDEPTHHI values for local queues match the enhanced binaries raw /metrics output after install and after update; the upstream-native binary is checked separately. Capture exact build/release identity and live scrape evidence, then tear down lab resources.
- [ ] #8 Document how the new metric can be retained by downstream scrape filtering and joined to queue-age metrics for per-queue alert policy selection, without embedding a customer-specific threshold mapping in this public repository.
- [ ] #9 The inventory also identifies running exporter services or known install paths outside the managed layout and reports their binary path, version, port and reason they cannot be updated automatically; it never silently claims these copies were upgraded.
<!-- AC:END -->
