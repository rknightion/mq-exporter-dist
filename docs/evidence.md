# Implementation evidence

Status: implementation under validation; no stable release acceptance.

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
  publication now fails closed until reviewed independent IBM receipts exist.

The initial native inspection found only GLIBC_2.2.5 and GLIBC_2.3.2 requirements.
Its upstream RPATH was identified and the build was adjusted using
`--enable-new-dtags`, without a collector patch. Subsequent release inspection must
verify RUNPATH on the exact candidate, architecture, interpreter and MQ imports.

Outstanding: final committed build identities and hashes; hosted CI; Windows build
and PowerShell 5.1 execution; actual RHEL service lifecycle; native kernel 4.18;
live MQ metrics and reconnection; Server 2019 runtime/lifecycle; independent SDK
publisher integrity verification; independently repeated byte reproducibility.

Resume from the exact committed source with the Candidate release workflow. It
produces candidate artifacts after platform checks. Publication additionally needs
the IBM signature/checksum receipt gate. The 9.3.0.27 signature package was located
in Fix Central, but its download redirected to authentication; browser access was
unavailable. The public checksum page does not list this version.
Private inputs, SDK libraries and uncommitted local test fixtures are not release
assets. No real queue manager, server or existing monitoring configuration was
modified during these checks.
