# MQ exporter distribution review

## Distribution scope

This repository packages upstream MQ exporters and their installers for Linux and Windows. Keep the distribution version distinct from the upstream version. Preserve the separate native and custom build paths and their documented compatibility claims.

## Artifact and release integrity

Review changes to the version grammar against `tests/version-vectors.json` and its callers. Check archive metadata, checksum verification and signing against the same accepted artifacts. Installer-only revisions preserve the previously accepted executable bytes. Keep IBM SDK and runtime files as build inputs.

## Lifecycle and rollback

Review Linux and Windows install behavior at their actual platform boundaries. For updates, check multiple-instance selection, configuration preservation, health verification and rollback after a failed candidate. Keep diagnostics and fixture identifiers synthetic.

## Verification

Run `just check` for Go and shell checks, PowerShell parsing and preflight, distribution regressions and the strict documentation build. Review native installation and live MQ acceptance against the documented platform matrix. A local syntax or packaging check supports only the behavior it exercises.

## Published compatibility

Check the compatibility table and installation instructions when changing supported inputs or platform behavior. Keep public examples free of credentials, host identifiers and diagnostics from deployed systems.
