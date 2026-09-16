# Maintaining the distribution

## Documentation site

`just docs-build` builds the GitHub Pages site from an explicit allowlist of the
existing public Markdown. Its Python environment and hash-locked MkDocs packages
are build-machine dependencies only. `just docs-lock` refreshes the lock after a
reviewed version change. Generated site output is privacy-scanned before upload.
The Documentation workflow builds pull requests and deploys only main, through the
`github-pages` environment. It does not publish binary releases.
Local docs staging and previous outputs stay in `.work/docs-*` and
`.work/site-previous-*` for maintainer-managed retention; the build never deletes
an existing output. Hosted runners dispose of their ephemeral workspaces.

## Exporter releases

1. Resolve the proposed upstream tag against IBM's remote and pin its exact commit.
   Review upstream changes, its Go minimum, vendored mq-golang version and all
   LICENSE/NOTICE files. Build a fresh pinned checkout, never an existing working
   tree. Record any essential patch separately; the initial build has no patch.
2. Select a supported patched Go release from [Go downloads](https://go.dev/dl/)
   and verify hashes from its JSON manifest. The current pin is Go 1.27.1.
   Check [minimum requirements](https://go.dev/wiki/MinimumRequirements)
   again, especially Windows cgo's DWARF 5 / binutils >=2.37 requirement.
3. Obtain MQ SDK/client inputs from [IBM's published acquisition route](https://www.ibm.com/docs/en/ibm-mq/9.3.x?topic=overview-redistributable-mq-clients).
   Keep these separately licensed inputs outside source and public payloads. The
   SDK inputs use IBM HTTPS downloads with pinned SHA-256 verification. Record
   their source, method and hash in `build/publisher-verification.json`; these
   locally calculated hashes are not IBM-published checksums. Do not use a newer
   SDK as proof of older-runtime compatibility. Inspect imported APIs and load
   against the intended older runtime.
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
Its matrix builds each exporter separately: four archives, one platform pair per
exporter. The `publish` input defaults to false, retaining build-only CI candidates.
When publication is explicitly enabled, it checks the bytes, verifies their hashes,
checks SDK integrity records against the pins, attests them and creates a prerelease.
Locally use `just build-linux VERSION otel` or `just build-windows VERSION otel`;
omitting the exporter selects Prometheus. Each archive has exactly one collector
and a configuration checker built from that collector's own upstream `config.go`.

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
