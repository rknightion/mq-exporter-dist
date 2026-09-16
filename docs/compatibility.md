# Compatibility and acceptance

All platform support is provisional. “Unavailable” is not a pass. Linux target
coverage is limited to RHEL 8.10 / glibc 2.28 and RHEL 9.x / glibc 2.34 on x86-64.
Windows targets Server 2019 amd64 (build 17763); the installer accepts only that
server build. Its MQ version and DLL set must be measured separately. No older or
newer Windows Server target is currently supported.

The matrix below records **Prometheus** evidence, including historical candidates
identified below. OTel is a separate package and earns each layer independently.
Container boot feasibility alone is not exporter proof.

| Evidence layer | EL8 build userspace + MQ 9.3.0.27 client | EL9 userspace | RHEL 8.10 kernel 4.18 + local MQ | Windows Server 2019 |
|---|---|---|---|---|
| Compile unchanged upstream | Passed local and hosted CI | Same Linux artifact | Same Linux artifact | Built on Server 2022; target unvalidated |
| Native loading / help | Passed local emulation and x86-64 CI | Passed exact CI archive, emulated x86-64 | Unavailable | Failed in bare Server Core (missing DLL); prerequisite retry timed out |
| Actual upstream config reader | Passed generated bindings configuration | Passed exact CI archive | Unavailable | Not reached in Server Core probe |
| Service lifecycle | Unavailable | Unavailable | Unavailable | Unavailable |
| Real MQ connection and queue metrics | Unavailable | Unavailable | Unavailable | Unavailable |
| Established connection loss / restart | Unavailable | Unavailable | Unavailable | Unavailable |

The local Docker host is ARM64. EL8/EL9 container checks share its VM kernel and use
x86-64 emulation. They do not validate a 4.18 kernel or native RHEL deployment.
Hosted Windows Server 2022 compilation, native loading, upstream-reader parsing,
PowerShell 5.1 Unicode configuration tests and synthetic SCM adapter lifecycle
passed in candidate run `35089700000`. These establish build-host evidence only;
neither the full Windows installer nor Server 2019 runtime acceptance is proven.
The Server Core 2019 Hyper-V probe booted successfully but exposed missing native
runtime prerequisites. The follow-up VC runtime bootstrap timed out before exporter
tests; see the evidence ledger for both failed/cancelled run identities.
See [exact hashes and run identities](evidence.md).

## Separate OTel candidate

Candidate run `35102719891` at `4510d3a41e23b2adbf3bddd89375675804299c8e` built
mq_otel v0.1.0-rc.3 packages independently; they are not published releases.

| Evidence layer | EL8 / EL9 userspaces | Windows Server 2022 build host | Target RHEL / Server 2019 |
|---|---|---|---|
| Compile unchanged upstream | Passed in EL8 | Passed | Target runtime validation separate |
| Native loading / help | Passed both | Passed | Unavailable |
| Actual OTel configuration reader | Passed both | Passed, including Unicode fixture | Unavailable |
| Service lifecycle | Mocked installer commands only | Synthetic SCM child fixture only | Unavailable |
| Real MQ queue metrics and OTLP receipt | Unavailable | Unavailable | Unavailable |
| Established connection loss / restart | Unavailable | Unavailable | Unavailable |

The same run refreshed Prometheus's EL8/EL9 loading and actual-reader evidence.
OTel's initial unavailable-MQ exit 1 and Prometheus's exit 10 were tested in the
network-isolated EL8 build userspace. These are not established-connection recovery
tests. Neither exporter has native RHEL kernel 4.18 acceptance yet.

## Missing acceptance commands

On an explicitly authorized Linux lab server with existing MQ 9.3.0.27 and a
synthetic `QM1`, first run `bash diagnose.sh /opt/mqm`. Record OS, architecture,
kernel, glibc and MQ versions without publishing host identifiers. Install the
candidate with the README command. Expect upstream-reader success before install,
an active `mq-exporter-qm1.service`, and health JSON with `connected:true,status:2`.
Compare queue metrics to a known `APP.QUEUE` fixture using the authorized lab's
existing permissions. Record both connection and coverage outcomes.

For startup failure, stop the exporter, make only the authorized disposable lab
queue manager unavailable, then start the service: expect exporter exit 10 and no
listener, followed by service retries. After starting that queue manager, expect
status 2 and queue samples. Next interrupt an established connection: expect the
listener to remain up with status 0, then recover to 2. Finally stop/restart the
service and verify no orphan exporter remains. Never perform these actions on an
unapproved or production queue manager.

On Server 2019, run `powershell.exe -NoProfile -File .\diagnose.ps1`. Establish
amd64, build 17763, MQ version/fix pack and installed runtime DLLs. Install using
the README command, then use `Get-Service`, `Stop-Service` and `Start-Service` on
`mq-exporter-qm1`, confirming the child's PID exits on stop and only one child runs
after restart. Repeat startup and established-connection scenarios above. Run the
generator with a Unicode password-file path and compare parsed output with Linux.
Check service-account read access and logs under the actual service identity.

Promotion requires these records for both Linux targets and Server 2019, exact
distribution commit and archive hashes, pinned SDK integrity verification,
license review, reproducibility comparison, and green checks at that commit.
The candidate workflow deliberately refuses stable version strings.
