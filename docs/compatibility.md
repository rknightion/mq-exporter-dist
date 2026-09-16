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

| Check | Linux EL8 / EL9 userspaces | Windows Server 2022 build host | Full RHEL / Server 2019 targets |
|---|---|---|---|
| Compilation | Passed in EL8 | Passed | Built binaries require target validation |
| Native loading and help | Passed in both userspaces | Passed | Not tested successfully |
| Upstream configuration reader | Passed for both exporters | Passed, including Unicode paths | Not tested |
| Service lifecycle | Installer tested with simulated systemd commands | Adapter tested with a synthetic child process | Not tested |
| Live MQ connection and queue metrics | Not tested | Not tested | Not tested |
| Reconnection and restart with MQ | Not tested | Not tested | Not tested |

EL8/EL9 containers do not establish operation on a RHEL host's kernel. Native
RHEL 8.10 kernel 4.18 validation remains outstanding. A Server Core 2019 container
also does not establish full-server installation, service-account permissions or
live MQ operation. Stable v0.1.0 remains unavailable until target acceptance.

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
