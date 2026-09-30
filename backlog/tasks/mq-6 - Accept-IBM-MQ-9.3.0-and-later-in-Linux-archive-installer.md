---
id: MQ-6
title: Accept IBM MQ 9.3.0 and later in Linux archive installer
status: Done
assignee: []
created_date: '2026-09-30 08:24'
updated_date: '2026-09-30 09:29'
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
- [x] #1 Linux installer accepts a well-formed installed MQ version at or above 9.3.0 for native and custom archives and rejects older or malformed versions before installation
- [x] #2 Docs and release notes state the new installer threshold and retain precise limits of native MQ testing
- [x] #3 Changed installer path has focused regression and integration proof; unchanged payloads match last accepted release by payload_sha256
- [x] #4 Publish native v6.0.0-2 and custom v6.0.0-custom-3 from verified exact source and report their release URLs
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. Implement and prove the shared version gate with synthetic boundary versions. 2. Update compatibility and release notes without claiming live acceptance. 3. Build and inspect exact native and custom candidates, compare unchanged payload hashes, review, commit and push. 4. Publish both tracks after the required gates and verify release assets.

Revision: Ordinary source builds changed unrelated payload hashes, so package the accepted binaries from v6.0.0-1 and v6.0.0-custom-2 through Candidate release CI. Verify source SHA256SUMS and known-releases per-member hashes, prove the packaged installer, then publish only the exact tested revised archives. Update release links and inventory afterward.
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
Shared Linux installer version gate now accepts synthetic MQ 9.3.0, 9.3.0.35, 9.4.0.1 and 10.0.0, rejecting 9.2 and malformed input. Disposable EL8 installer integration passed for existing native and custom archives with mocked 9.3.0.35 output; no live MQ connection or native host acceptance was run. The current EL8 repository lacks pinned GCC 8.5.0-28, so the build pin was refreshed to available 8.5.0-29 and the recorded image digest reconciled before release builds.

Ordinary source-build candidate runs 36692527613 (native) and 36692530793 (custom) succeeded at d541a70 but changed unrelated executable hashes, so they will not be published. The archive revision path verifies prior release SHA256SUMS and known-releases per-member hashes, then changes only the Linux installer, versioned SBOM and metadata. Local revised Linux archives passed the packaged-script integration fixture for native Prometheus, native OTel and custom Prometheus with synthetic MQ 9.3.0.35.

Published v6.0.0-2 and v6.0.0-custom-3 at exact source SHA 327974bcf2e2613a5f4869f91c39d60472af04f1. Candidate CI runs 36695360242 (native) and 36695209819 (custom) succeeded. Read-back archives and checksum sidecars were byte-identical to those CI artifacts; SHA256SUMS and GitHub attestations verified for every archive. Per-member comparison proved only Linux install.sh and versioned SBOM changed from accepted bases, with Windows changing only versioned SBOM. Disposable container tests exercised the packaged Linux installer with synthetic MQ version output; native/live MQ retesting was intentionally not performed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Linux archive installers now accept MQ 9.3.0 and newer in both tracks. Published v6.0.0-2 and v6.0.0-custom-3 from verified prior-release executable bytes; local packaged-installer tests, exact-SHA candidate CI, payload comparison, release readback and attestations passed. Updated release docs and accepted-release inventory.
<!-- SECTION:FINAL_SUMMARY:END -->
