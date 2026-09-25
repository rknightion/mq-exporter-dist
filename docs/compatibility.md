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
| Recovery after losing an established MQ connection | Not tested | Passed in local bindings | Passed in local bindings |

Native tests used RHEL 8.10 with kernel `4.18.0-553.158.1.el8_10.x86_64`
and glibc 2.28, RHEL 9.6 with kernel `5.14.0-570.132.1.el9_6.x86_64`
and glibc 2.34, and Windows Server 2019 build 17763 with PowerShell 5.1.
SELinux remained enforcing on both RHEL hosts. Earlier loading and lifecycle
checks used the MQ 9.3.0.27 client runtime; Windows also used Microsoft VC runtime
14.44.35211.0. Subsequent live checks used a native MQ 9.3.0.35 trial server.

Both exporters' `v6.0.0-rc.1` archives passed native installation, upgrades from
`v0.1.0-rc.8`, reboot startup and service removal on all three platforms.
These installer checks used the MQ 9.3.0.27 client runtime, without a running
queue manager. Windows checks included paths containing spaces and Unicode.

Coverage includes preserved configuration and executable backups, rejected
checksum and identity changes, independent instances, stop/start, automatic
startup after reboot, and service removal without deleting configuration.

## v6.0.0-1, v6.0.0-custom-1 and v6.0.0-custom-2

These releases have the same upstream source and exporter binaries as v6.0.0,
plus the custom track. Their Linux candidates passed these checks on a
native RHEL 9.6 host (kernel `5.14.0-570.132.1.el9_6`, glibc 2.34, SELinux enforcing),
with a native MQ 9.3.0.35 trial server and two queue managers. The exporters used
the MQ 9.3.0.27 redistributable client in client mode, authenticating with a
password on one queue manager:

- **QDEPTHHI gauge.** For every monitored local queue, `ibmmq_queue_attribute_depth_high_limit`
  equalled `DISPLAY QLOCAL QDEPTHHI` exactly, in both directions. This covered values
  of 0, 35, 80, 90 and 100, both queue-pattern forms, and an alias queue that produced
  no sample. `ALTER`, `DEFINE` and `DELETE QLOCAL` were reflected after rediscovery,
  with no stale samples. Upstream-native builds emitted no custom gauge.
- **Multiple instances.** Six simultaneous instances ran on separate ports under
  two installation roots, including a custom root with an administrator SELinux file-context
  mapping and client-data unit drop-ins. The mix was native and custom Prometheus
  instances plus one OTel instance.
- **Updater.** Tested with real systemd:
  - dry-run inventory;
  - a v6.0.0 install without release records (named by its published hash);
  - an unmanaged exporter process (reported with version and listening port);
  - successive updates of every instance, preserving configuration edits,
    identity, ports, ownership, SELinux labels, drop-ins and enablement;
  - an injected mid-update failure that rolled back cleanly and stopped;
  - an idempotent rerun, and a new `install.sh --custom` instance.
- **Variant switching** (v6.0.0-1 and v6.0.0-custom-2 updaters). `update.sh --custom`
  moved native instances to the custom build, and `update.sh --native` moved every
  Prometheus instance back. Each switched instance ran the other binary, matched
  MQSC (custom) or emitted no custom gauge (native), and kept its configuration.
  v6.0.0-custom-1's updater keeps each instance on its own build.
- **Reboot.** After a host reboot with MQ not yet started, every instance retried
  and recovered on its own once the queue managers started.

The Windows archives in v6.0.0-1 carry exporter, configuration-checker and
service-wrapper executables byte-identical to v6.0.0. `mq-dist.exe` and
`install.ps1` changed: new helper commands and the release grammar. They passed
build-host runtime checks but were **not retested on native Server 2019**. RPMs
are unchanged; v6.0.0 RPMs remain current.

## Live MQ coverage and remaining limits

The `v6.0.0-rc.1` Linux RPMs and Windows archives passed these checks on the
native hosts listed above:

- Local bindings to a native MQ 9.3.0.35 queue manager under a non-administrator
  service account with explicit MQ permissions.
- Prometheus connection status and exact queue depth, alongside decoded OTLP/HTTP
  queue metrics with matching queue-manager attributes and fresh timestamps.
- MQ shutdown/restart and exporter service restarts. Prometheus retained its
  process and reported status 0 during the outage; OTel recovered through
  systemd or the SCM wrapper. Both exporters reported the queue's new depth
  after reconnection, matching an independent MQ inquiry.

The signed RPMs passed installation and running-service upgrades on both RHEL
hosts with SELinux enforcing. Upgrades preserved configuration and did not
restart running exporter processes. The Linux archive installer still requires
MQ 9.3.0.27; the RPM tests do not establish that this installer accepts .35.
RPM reboot startup and recovery passed on both hosts. RHEL 8 also passed removal
of both exporters with configuration retained. On RHEL 9, Prometheus exporter
removal stopped its instances and removed enablement links, but systemd retained
stale unit state. The package now explicitly reloads systemd after removal;
the corrected scriptlet has not repeated the native RHEL 9 removal test.

Earlier rc.4 binary tests also covered authenticated loopback client connections,
MQ recovery and queue exclusions. Linux loaded the MQ 9.3.0.27 redistributable
client against a .35 server; Windows used the installed .35 runtime. That client
connection cycle has not been repeated with the final `v6.0.0-rc.1` packages.

**MQ 9.3.0.27 server/local-bindings acceptance remains untested.** A .27 client
connecting to a .35 server does not establish it. MQ TLS, authenticated OTLP
forwarding and non-loopback network paths are also untested. The OTLP receiver
was local, not a Grafana Cloud destination. These results do not establish other
MQ fix packs, operating-system versions or deployment configurations.

The installers target full servers, not container deployments. A tested Server
Core image reports a workstation product type and is rejected by the installer's
server-only platform check. Use a Server 2019 VM or host for installation.

Container checks alone do not establish host-kernel or full-server acceptance.
The native tests above cover the listed kernel builds, not every RHEL update or
MQ installation. Distribution release numbering follows IBM's exporter source;
it does not establish compatibility with an untested MQ runtime.

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
