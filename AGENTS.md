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

## Tracking work

Work is tracked in this repository's GitHub issues; they are the only queue. Do not add a checklist
file such as `ROADMAP.md` beside them.

- A pull request body says how it relates to an issue, on a line of its own: `Closes #N` with the
  `Acceptance evidence` table from `.github/pull_request_template.md` (one row for each acceptance
  criterion of that issue), `Refs #N` when it only relates to one, or `Task: none, <reason>`.
- A pull request that changes `.github/workflows/` or `.github/actions/` carries no closing keyword:
  write `Task: none, <reason>`, with `Refs #N` beside it if you like.
- Contributors never need the project board or the tracker tooling; a maintainer handles both.
- Issues and pull requests are public, so they carry no real identifiers: no email addresses,
  handles, account ids, host or device names, addresses or coordinates. Write the shape, not the
  instance.
- Older commits and docs cite legacy board ids such as `MQ-1`. `just issue <ID>` prints the issue
  each one became; `.github/tracker/id-map.json` is the map.

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

Go build inputs and generated service-module directives must match the justfile toolchain.
The distribution publishes archives and RPMs, not runtime container images;
container CA checks describe build and validation inputs only.

The docs venv uses Python 3.13 to preserve binary-only PyYAML/watchdog installs
on Linux and macOS; general build tooling remains on its separate Python pin.
The image trust workaround copies the exact AAA Certificate Services and
emSign ECC Root CA - G3 roots from https://emudhra.we-have-a-problem.com/roots.json
into the RHEL blacklist/blocklist paths; it does not imply a patched ca-certificates RPM.
