# Repository instructions

This is a generic public community distribution of IBM's MQ exporter. Use only
synthetic examples. Never import private diagnostics, identifiers, paths or history.
Inspect staged files, artifacts and metadata for secrets and private material before
any upload, commit or release. IBM MQ SDK/runtime files are build inputs only.

This repository is explicitly exempt from Backlog. Do not initialize a tracker.
Maintain implementation evidence and compatibility boundaries in `docs/`.

## Task interface

The developer and CI task interface is the top-level justfile. `just check` is the
pre-commit gate. Do not claim unavailable native or live MQ tests passed.

Build the pinned upstream commit with vendored dependencies; do not change the
collector. Keep distribution and upstream versions separate. Stable releases need
all acceptance layers in `docs/compatibility.md`. Preserve unrelated work.
