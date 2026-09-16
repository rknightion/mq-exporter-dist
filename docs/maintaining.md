# Maintaining the distribution

1. Resolve the proposed upstream tag against IBM's remote and pin its exact commit.
   Review upstream changes, its Go minimum, vendored mq-golang version and all
   LICENSE/NOTICE files. Build a fresh pinned checkout, never an existing working
   tree. Record any essential patch separately; the initial build has no patch.
2. Select a supported patched Go release from [Go downloads](https://go.dev/dl/)
   and verify hashes from its JSON manifest. The initial pin is Go 1.26.8, one of
   the two supported release families when selected. Check [minimum requirements](https://go.dev/wiki/MinimumRequirements)
   again, especially Windows cgo's DWARF 5 / binutils >=2.37 requirement.
3. Obtain MQ SDK/client inputs from [IBM's published acquisition route](https://www.ibm.com/docs/en/ibm-mq/9.3.x?topic=overview-redistributable-mq-clients).
   Keep these separately licensed inputs outside source and public payloads. The
   initial SDK hashes were calculated from IBM HTTPS downloads; independent
   publisher-signature validation is still pending. Do not represent those hashes
   as IBM-published checksums. Do not use a newer SDK as proof of older-runtime
   compatibility. Inspect imported APIs and load against the intended older runtime.
4. Update `build/inputs.json`, the Linux Dockerfile and workflow toolchain versions
   together. Pin action/reusable SHAs after reading their inputs and permissions.
   Record compiler/linker versions, the final local build-image digest and full RPM
   inventory. The base image and requested package versions are pinned; transitive
   RPM resolution is recorded but is not yet a fully archived reproducible toolchain.
5. Run `just check`, the platform builds and all applicable acceptance layers. Rebuild
   independently and compare executable/archive hashes before claiming bit-for-bit
   reproducibility. The initial Linux local/CI comparison matched every executable
   but differed in metadata's constructed image identity. Whole-archive
   reproducibility needs a reproducible final image or separation of that
   invocation-specific identity into external provenance, followed by comparison.
   Run CodeRabbit on this public repository, inspect staged and generated content,
   and commit/push the exact reviewed source before building release archives.

Use **Candidate release** to build both platforms at the workflow's exact SHA.
It builds once, checks the bytes, uploads those same archives, verifies their hashes,
requires independent SDK verification, attests them and creates a prerelease.
`just publish-check` currently blocks releases: the separate IBM signature package
for 9.3.0.27 requires Fix Central authentication. Obtain it through
[IBM's signature route](https://ibm.biz/mq93signatures), verify the archives using
[IBM's documented commands](https://www.ibm.com/docs/en/ibm-mq/9.3.x?topic=overview-mq-code-signatures),
and record the authenticated source URL, method and matching SHA-256 for each input
in `build/publisher-verification.json` through normal code review. Do not fill these
receipts from the locally calculated hashes alone. Unpublished CI candidate artifacts
remain available for evaluation while this gate is blocked.

It never rebuilds at publication. Artifact
metadata includes the exact distribution SHA and upstream SHA. SDK/runtime files
are excluded by the packager's explicit allowlist; notices are assembled from
upstream and vendored licenses. The CycloneDX inventory includes vendored modules
(including modules not linked into this particular collector); it is an inventory,
not a vulnerability clearance.

The unchanged exporter uses dynamically linked MQ native APIs. The config-check
utility combines unchanged upstream `config.go` with a small entrypoint calling
`initConfig`, without invoking MQCONN. IBM's pruned vendor tree omits the service
package. The Windows adapter therefore builds in a separate module using a
checksum-pinned x/sys v0.45.0 archive, matching the collector's dependency version.
Its acquisition is explicit and its compilation is offline; IBM's vendor tree is
unchanged. The adapter contains no metrics implementation. Review the adapters
independently when changing service behavior.

Read-only diagnostics emit platform/runtime information without machine names or
queue-manager inventories. Keep any detailed local investigation output private.
Repository history and release metadata must remain generic.

Local successful build workspaces are archived under `.work/completed/`; failed
build workspaces stay at `.work/build-*` for diagnosis. Download caches stay under
`.work/downloads/`. They contain separately licensed inputs, are never uploaded,
and require maintainer-managed archival/retention. Hosted runners dispose of their
ephemeral workspaces. No build cleanup deletes existing local evidence.
