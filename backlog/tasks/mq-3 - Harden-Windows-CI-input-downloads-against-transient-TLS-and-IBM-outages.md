---
id: MQ-3
title: Harden Windows CI input downloads against transient TLS and IBM outages
status: To Do
assignee: []
created_date: '2026-09-25 13:35'
updated_date: '2026-09-25 13:35'
labels: []
dependencies: []
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Two v6.0.0-1 publish attempts failed on the Windows runner for reasons unrelated to source: public.dhe.ibm.com timed out (curl 28), and schannel failed the revocation check on the pinned toolchain download (CRYPT_E_REVOCATION_OFFLINE). build.py downloads with --retry 3 only.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Windows downloads survive a revocation-server outage without disabling certificate validation
- [ ] #2 Transient connect failures retry with backoff
- [ ] #3 A failed input download names the input and suggests re-running the failed job
<!-- AC:END -->
