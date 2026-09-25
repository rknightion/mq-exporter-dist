---
id: MQ-2
title: Reconcile linux build image digest with recorded build input
status: To Do
assignee: []
created_date: '2026-09-25 10:12'
labels: []
dependencies: []
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
build/linux.Dockerfile pins registry.access.redhat.com/ubi8/ubi@sha256:45efff7... (Renovate-updated) while build/inputs.json linux_image records sha256:91e8320..., so build-metadata inputs.linux_image does not describe the image actually used. Found during MQ-1 plan review.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 build/inputs.json linux_image equals the Dockerfile FROM digest,A check in just check fails when they diverge,Renovate updates both together
<!-- AC:END -->
