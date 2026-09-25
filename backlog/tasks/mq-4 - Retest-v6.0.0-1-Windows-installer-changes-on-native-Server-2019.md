---
id: MQ-4
title: Retest v6.0.0-1 Windows installer changes on native Server 2019
status: To Do
assignee: []
created_date: '2026-09-25 13:35'
updated_date: '2026-09-25 13:35'
labels: []
dependencies: []
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
v6.0.0-1 Windows archives changed install.ps1 (release grammar) and mq-dist.exe (new helper commands) versus v6.0.0; the exporter, config-check and service executables are byte-identical. Published with a documented limit after build-host checks only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Native Server 2019 install and upgrade from v6.0.0 to v6.0.0-1 pass for both exporters
- [ ] #2 docs/compatibility.md records the result and removes the limit
<!-- AC:END -->
