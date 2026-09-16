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
| Live MQ connection and queue metrics | Not tested | Not tested | Not tested |
| Recovery after losing an established MQ connection | Not tested | Not tested | Not tested |

Native tests used RHEL 8.10 with kernel `4.18.0-553.158.1.el8_10.x86_64`
and glibc 2.28, RHEL 9.6 with kernel `5.14.0-570.132.1.el9_6.x86_64`
and glibc 2.34, and Windows Server 2019 build 17763 with PowerShell 5.1.
SELinux remained enforcing on both RHEL hosts. All three used the MQ 9.3.0.27
client runtime; Windows also used Microsoft VC runtime 14.44.35211.0.

The Linux lifecycle checks covered Prometheus rc.1-to-rc.3 upgrades and separate
OTel rc.3 installation. Windows checks passed with the packaged rc.4 installers,
including rc.1-to-rc.4 upgrades and separate rc.4 instances. Reboot checks used
the same corrected installer with rc.3 binaries; all four rc.4 exporter binaries
are byte-identical to rc.3. The older Windows installer failed an ACL identity lookup
on a full server; use the corrected installer, not the rc.1 or rc.3 copy.

Coverage includes preserved configuration and executable backups, rejected
checksum and identity changes, independent instances, stop/start, automatic
startup after reboot, and service removal without deleting configuration.
These tests do not establish successful local bindings or remote MQ connections:
no queue manager was present. TLS, queue metrics and OTLP delivery still require
a licensed lab with a live queue manager.

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
MQ installation. Stable v0.1.0 remains unavailable until live MQ acceptance.

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
