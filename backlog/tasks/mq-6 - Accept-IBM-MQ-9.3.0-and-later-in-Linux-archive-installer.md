---
id: MQ-6
title: Accept IBM MQ 9.3.0 and later in Linux archive installer
status: In Progress
assignee: []
created_date: '2026-09-30 08:24'
updated_date: '2026-09-30 08:52'
labels: []
dependencies: []
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
The shared Linux archive installer rejects servers whose installed MQ runtime is newer than the exact initial 9.3.0.27 build, blocking native and custom deployment. Ship updated native and custom archives while preserving the distinction between accepted installer versions and runtime combinations actually tested.
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Linux installer accepts a well-formed installed MQ version at or above 9.3.0 for native and custom archives and rejects older or malformed versions before installation
- [ ] #2 Docs and release notes state the new installer threshold and retain precise limits of native MQ testing
- [ ] #3 Changed installer path has focused regression and integration proof; unchanged payloads match last accepted release by payload_sha256
- [ ] #4 Publish native v6.0.0-2 and custom v6.0.0-custom-3 from verified exact source and report their release URLs
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Implement and prove the shared version gate with synthetic boundary versions. 2. Update compatibility and release notes without claiming live acceptance. 3. Build and inspect exact native and custom candidates, compare unchanged payload hashes, review, commit and push. 4. Publish both tracks after the required gates and verify release assets.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Shared Linux installer version gate now accepts synthetic MQ 9.3.0, 9.3.0.35, 9.4.0.1 and 10.0.0, rejecting 9.2 and malformed input. Disposable EL8 installer integration passed for existing native and custom archives with mocked 9.3.0.35 output; no live MQ connection or native host acceptance was run. The current EL8 repository lacks pinned GCC 8.5.0-28, so the build pin was refreshed to available 8.5.0-29 and the recorded image digest reconciled before release builds.
<!-- SECTION:NOTES:END -->
