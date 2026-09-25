---
id: MQ-5
title: Refresh the native Linux install-cycle test for current release tracks
status: To Do
assignee: []
created_date: '2026-09-25 13:35'
updated_date: '2026-09-25 13:35'
labels: []
dependencies: []
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
tests/linux-native-install.sh is hard-wired to v0.1.0 rc inputs and a host without mqmon, so it could not run in the MQ-1 lab. The lab exercised lifecycle, updater and reboot directly.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 The test takes explicit native and custom archives and versions
- [ ] #2 It covers install, upgrade, updater, variant switch, reboot and removal on a disposable VM
- [ ] #3 just native-linux-install-cycle documents its inputs
<!-- AC:END -->
