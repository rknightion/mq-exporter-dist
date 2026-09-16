# Compatibility

All platform support is provisional. Check these limits before deploying a
candidate; a successful build is not a full server acceptance test.

## Initial platform targets

| Platform | Architecture | Required runtime |
|---|---|---|
| RHEL 8.10 | x86-64 | glibc 2.28, IBM MQ 9.3.0.27 |
| RHEL 9.x | x86-64 | glibc 2.34, IBM MQ 9.3.0.27 |
| Windows Server 2019, build 17763 | amd64 | Existing 64-bit IBM MQ installation; version and DLL set must be validated |

The Linux archive targets both listed RHEL versions. Other Linux distributions
and Windows Server versions are outside the initial target set.

MQ native libraries are required at runtime. Linux binaries are dynamically
linked, not fully static. Neither MQ libraries nor glibc are included in downloads.
Windows also needs the prerequisites of its installed MQ runtime. MQ 9.3.0.27
client imports include `VCRUNTIME140.dll` and `VCRUNTIME140_1.dll` from the
[Microsoft x64 Visual C++ v14 runtime](https://learn.microsoft.com/en-us/cpp/windows/latest-supported-vc-redist).
The exporter installer does not install that runtime.

## What has been tested

The separate Prometheus and OpenTelemetry candidate packages have the following
validation coverage. “Not tested” is not a pass.

| Check | Linux build and container checks | Native RHEL 8.10 / 9.6 | Native Windows Server 2019 |
|---|---|---|---|
| Compilation | Passed in EL8 | Precompiled binaries tested | Built on Server 2022 |
| Native loading and help | Passed in EL8 and EL9 | Passed | Passed |
| Upstream configuration reader | Passed for both exporters | Passed | Passed, including Unicode paths |
| Install, upgrade and service lifecycle | Simulated systemd tests | Passed with real systemd | Passed with real SCM and dedicated account |
| Reboot startup and unavailable-MQ retries | Not covered by containers | Passed | Passed |
| Live MQ connection and queue metrics | Not tested | Passed with the runtime combinations below | Passed with MQ 9.3.0.35 |
| Recovery after losing an established MQ connection | Not tested | Passed in local bindings and authenticated client mode | Passed in local bindings and authenticated client mode |

Native tests used RHEL 8.10 with kernel `4.18.0-553.158.1.el8_10.x86_64`
and glibc 2.28, RHEL 9.6 with kernel `5.14.0-570.132.1.el9_6.x86_64`
and glibc 2.34, and Windows Server 2019 build 17763 with PowerShell 5.1.
SELinux remained enforcing on both RHEL hosts. Earlier loading and lifecycle
checks used the MQ 9.3.0.27 client runtime; Windows also used Microsoft VC runtime
14.44.35211.0. Subsequent live checks used a native MQ 9.3.0.35 trial server.

The Linux lifecycle checks covered Prometheus rc.1-to-rc.3 upgrades and separate
OTel rc.3 installation. Windows checks passed with the packaged rc.4 installers,
including rc.1-to-rc.4 upgrades and separate rc.4 instances. Reboot checks used
the same corrected installer with rc.3 binaries; all four rc.4 exporter binaries
are byte-identical to rc.3. The older Windows installer failed an ACL identity lookup
on a full server; use the corrected installer, not the rc.1 or rc.3 copy.

Coverage includes preserved configuration and executable backups, rejected
checksum and identity changes, independent instances, stop/start, automatic
startup after reboot, and service removal without deleting configuration.

## Live MQ coverage and remaining limits

Both rc.4 exporters passed these checks on RHEL 8.10, RHEL 9.6 and Server 2019:

- Local bindings to a native MQ 9.3.0.35 queue manager under a non-administrator
  service account with explicit MQ permissions.
- Prometheus connection status and exact queue depth, alongside decoded OTLP/HTTP
  queue metrics with matching queue-manager attributes and fresh timestamps.
- Queue depth changing from 3 to 5 across MQ shutdown/restart, followed by exporter
  service restarts. Prometheus retained its process and reported status 0 during
  the outage; OTel exited and recovered through systemd or the SCM wrapper.
- Authenticated, loopback TCP client connections. Linux loaded the MQ 9.3.0.27
  redistributable client; Windows used the installed MQ 9.3.0.35 runtime. Both
  exporters recovered after MQ shutdown/restart and service restarts, with queue
  depth changing from 5 to 7. The excluded queue was absent from both outputs.

The Linux local-bindings trial used a lab-only installer adaptation for the .35
version and IBM's `mqm` directory ownership. The ownership check is corrected in
rc.5; parent directories and the exporter installation still require
root ownership. The shipped Linux installer continues to require MQ 9.3.0.27.
It does not accept the .35 trial merely because these binary tests passed.
The rc.5 exporter executables are byte-identical to those tested from rc.4;
the rc.5 archives have not repeated the complete native installation cycle.

**MQ 9.3.0.27 server/local-bindings acceptance remains untested.** A .27 client
connecting to a .35 server does not establish it. MQ TLS, authenticated OTLP
forwarding and non-loopback network paths are also untested. The OTLP receiver
was local, not a Grafana Cloud destination. These results do not establish other
MQ fix packs, operating-system versions or deployment configurations.

The published Prometheus `v0.1.0-rc.1` Windows package also passed PE inspection,
native loading, the actual upstream configuration reader and the expected exit
code 10 when MQ is unavailable in a Hyper-V-isolated Server Core 2019 container
(build 17763, PowerShell 5.1). This used the MQ 9.3.0.27 client and Microsoft x64
VC runtime 14.44.35211.0. This check does not cover the OTel package or a full
exporter installation and service lifecycle on Server 2019.

The installers target full servers, not container deployments. The tested Server
Core image reports a workstation product type and is rejected by the installer's
server-only platform check. Full installation acceptance requires a Server 2019 VM
or host; the native-loading checks above do not bypass that requirement.

Container checks alone do not establish host-kernel or full-server acceptance.
The native tests above cover the listed kernel builds, not every RHEL update or
MQ installation. Stable v0.1.0 remains unavailable until the remaining target
acceptance is complete.

## Check your server

The archive includes a read-only diagnostic script. Run it before installation:

```bash
bash diagnose.sh /opt/mqm
```

On Windows, use 64-bit Windows PowerShell 5.1:

```powershell
powershell.exe -NoProfile -File .\diagnose.ps1
```

Confirm OS, architecture, MQ version and native runtime prerequisites. Keep
diagnostic output private if it contains details of your environment.
