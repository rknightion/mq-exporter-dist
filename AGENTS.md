# Repository instructions

This is a generic public community distribution of IBM's MQ exporter. Use only
synthetic examples. Never import private diagnostics, identifiers, paths or history.
Inspect staged files, artifacts and metadata for secrets and private material before
any upload, commit or release. IBM MQ SDK/runtime files are build inputs only.

Keep internal investigation records in ignored local storage. Public `docs/`
contains user instructions and compatibility limits, not internal run histories.

## Task interface

The developer and CI task interface is the top-level justfile. `just check` is the
pre-commit gate. Do not claim unavailable native or live MQ tests passed.

## Release tracks

- Native track (`vX.Y.Z`, `vX.Y.Z-N`, `-rc.M` candidates): build the pinned upstream
  commit with vendored dependencies, unchanged.
- Custom track (`vX.Y.Z-custom-N`): the Linux Prometheus build with only the reviewed
  patches in `build/patches/`, recorded in build metadata and the SBOM. Never patch
  the collector outside that directory, and never apply patches to native builds.
- `build/versions.py` owns the grammar and `tests/version-vectors.json` pins it for
  every language. SemVer tools sort `vX.Y.Z-N` below `vX.Y.Z`; always compare with it.
- Keep distribution and upstream versions separate.
- Native and custom Linux archives share `install.sh`; its MQ 9.3.0-or-newer
  gate is not proof of live acceptance for every runtime version.
- For an installer-only revision, use Candidate release `source_release` to
  retain accepted executable bytes; do not publish unrelated rebuild drift.
- A stable release needs acceptance, per `docs/compatibility.md`, for every surface
  it changes. Before publishing, prove that unchanged surfaces are byte-identical to
  the last accepted release (archive metadata `payload_sha256`), and document any
  change that was not natively retested.
