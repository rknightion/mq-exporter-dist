# Implementation evidence

Status: candidate implementation delivered; no stable release acceptance.

## Exact candidate evidence

Candidate **v0.1.0-rc.2** was built from distribution commit
`dc958206f6b2494ac4c9910a82c017894eea0beb` (initial implementation:
`fbc23f9f1d5a1c6990641d48993a83149033e423`).

- [Checks 35089701182](https://github.com/rknightion/mq-exporter-dist/actions/runs/35089701182):
  passed, including the source gate, actionlint and zizmor.
- [Candidate 35089700000](https://github.com/rknightion/mq-exporter-dist/actions/runs/35089700000):
  Linux and Windows build jobs passed. Publication **failed at the expected SDK
  verification gate**; attestation and GitHub Release publication did not run.
- CI artifacts: `candidate-linux` ID `10443593520`; `candidate-windows` ID
  `10444026201`. Retention is 14 days. The tested bytes were downloaded locally
  into `dist/`, hash-checked, indexed in `SHA256SUMS`, and privacy-scanned again.
- Earlier candidate run `35089019085` failed on Windows cgo argument quoting and
  Linux test-SDK ownership. Both were repaired without collector changes or
  weaker installer checks. The repair passed a two-file CodeRabbit review with
  zero findings and local integration before the successful candidate run.

| Candidate archive | SHA-256 |
|---|---|
| `mq-exporter-dist-v0.1.0-rc.2-linux-amd64.tar.gz` | `dfec53f37a5c27bd6941646f7a3f1699662c4906df64865c32ce76118af98a2e` |
| `mq-exporter-dist-v0.1.0-rc.2-windows-amd64.zip` | `873ede8f50bce5f8a0a46feb8638b7b93396c0f62297435b045280632469da30` |

Both archives include executable(s), installers/diagnostics, licenses/notices,
build metadata and a CycloneDX SBOM. No IBM MQ runtime is bundled.

The Windows job used Server 2022, Go 1.26.8, GCC 16.2.0 and binutils
2.47.20260726. Native loading, the actual upstream reader, PowerShell 5.1 Unicode
configuration serialization, and SCM adapter start/synthetic-child restart/stop
passed. The full Windows installer and actual exporter service identity/lifecycle
remain unvalidated on Server 2019. Metadata conservatively leaves the product's
service-lifecycle acceptance unavailable; the synthetic adapter test is narrower.
PE imports are MQ's `mqm.dll`, KERNEL32 and Windows UCRT API sets; no MSYS2 or
compiler DLL import was observed in the exporter.

The exact CI Linux archive passed loading with eager symbol resolution and
upstream configuration parsing in pinned EL9 userspace after download. EL8 native
loading, ELF inspection, actual-reader validation and installer integration passed
in CI. Systemd commands in installer integration were mocked, not lifecycle-tested.

An independent local Linux rebuild at the same commit produced identical bytes
for every payload except `build-metadata.json`. The only differing evidence field
was the locally constructed image identity. Thus executable reproducibility was
observed, but **whole-archive byte reproducibility is not established**. The local
archive hash is `18739b32374691330d5ea5f37b3c042330be7f798ddc0aff78afb79554046399`.
It is archived separately and is not substituted for the CI candidate.
The common exporter SHA-256 is
`2afe26476bdd8842072aafcd01533c39e50fa276cdc5ddb932e578dae9864f65`.

## Implementation checks

Upstream tag v6.0.0 was checked against both Git transport and GitHub's ref API:
`7bce9b8ef9ef513ff77688f022929843d5ba7eaf`. A fresh checkout compiled unchanged
against MQ SDK 9.3.0.27 in pinned UBI8 x86-64 userspace using Go 1.26.8.

Verified locally during implementation:

- Go regression tests for configuration, exact metric/label/value health parsing,
  truncated HTTP bodies, identity isolation, exclusive backups and injected
  partial-copy/backup/rename failure preservation.
- Bash syntax, shellcheck, PowerShell syntax parsing, archive checksum/layout tests
  (corrupt, truncated, mismatched, traversal, link, duplicate, unexpected entries),
  existing scratch preservation and command-local library environments.
- Native exporter loading and actual upstream configuration parsing in EL8 and EL9
  userspaces. These were x86-64 emulation tests on an ARM64 Docker host.
- First connection to unavailable synthetic QM1 exits 10 in a network-isolated
  client-only environment. Established-connection loss remains unavailable.
- Actual MQ libcurl conflict reproduced using an isolated library search directory:
  MQ libcurl lacks HTTPS; the command-local system library path restores HTTPS.
- Linux installer integration with real binaries and upstream reader, mocked
  systemctl commands: fresh install, preserved upgrade, backups, identity/port
  conflict rejection, multiple instances, path spaces and failed smoke preservation.
  This is not systemd service lifecycle evidence.
- Initial CodeRabbit review completed with 39 reviewed files and three findings:
  candidate platform pairing, stale test log counting and precise Windows build
  wording. All three were addressed; no finding was dismissed.
- Installer-only review completed with five reports (three distinct issues).
  Scratch/lock cleanup and offline argument validation were fixed. Failed upgrades
  now report manual service recovery; automatic restart after a partial update was
  deliberately not added because it could run mixed configuration and binaries.
- Build-only review completed with six reports (five distinct issues): SCM startup
  state, independent SDK verification, workspace retention, SBOM roots and Linux
  private-path scanning. Startup state, SBOM and scanning were fixed; successful
  workspaces are archived rather than deleted under the retention policy. Release
  publication checks reviewed SDK integrity records against the build pins.

The initial native inspection found only GLIBC_2.2.5 and GLIBC_2.3.2 requirements.
Its upstream RPATH was identified and the build was adjusted using
`--enable-new-dtags`, without a collector patch. Subsequent release inspection must
verify RUNPATH on the exact candidate, architecture, interpreter and MQ imports.

Outstanding: actual RHEL service lifecycle; native kernel 4.18; local bindings and
live MQ metrics/reconnection; Server 2019 runtime and full installer lifecycle;
whole-archive reproducibility and an independently repeated Windows build.
No unavailable check is a pass.

SDK integrity records now accept IBM HTTPS downloads with pinned SHA-256 checks;
the Windows ZIP also passed strict JAR signature verification. The earlier SDK
publication blocker is resolved. Resume with the Candidate release workflow at
the reviewed commit; platform acceptance remains provisional.
Private inputs, SDK libraries and uncommitted local test fixtures are not release
assets. No real queue manager, server or existing monitoring configuration was
modified during these checks.
