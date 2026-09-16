# Install on Windows

The PowerShell installer installs a precompiled exporter with a Windows service
adapter. Windows Server 2019 amd64 is a provisional target.

## Before you install

Use elevated, 64-bit **Windows PowerShell 5.1**. PowerShell 7 and a compiler are
not required. Check [compatibility](compatibility.md) and the native prerequisites
of your existing 64-bit IBM MQ installation, including its Visual C++ runtime.

Provision a dedicated account with MQ permissions and the **Log on as a service**
right. The installer does not grant those permissions. Do not use an administrator
account for the service.

Download `install.ps1` from a reviewed repository revision, or extract it from a
verified release ZIP. Choose an explicit version from
[GitHub Releases](https://github.com/rknightion/mq-exporter-dist/releases).

## Install Prometheus

For an existing local queue manager `QM1`:

```powershell
$credential = Get-Credential 'EXAMPLE\mqmon'
.\install.ps1 -Version v0.1.0-rc.1 -Instance qm1 -QueueManager QM1 `
  -ServiceAccount 'EXAMPLE\mqmon' -ServiceCredential $credential -Port 9157
```

Use `-MQPath` for a non-default MQ installation and `-InstallRoot` to change the
exporter installation directory. Quote paths containing spaces. Passwords are
supplied through the credential prompt, not command-line arguments.

```powershell
Get-Service mq-exporter-qm1
Get-Content 'C:\Program Files\mq-exporter\qm1\logs\exporter.log' -Tail 50
& 'C:\Program Files\mq-exporter\qm1\mq-dist.exe' health --qmgr QM1 --url http://127.0.0.1:9157/metrics
```

Expect `connected:true,status:2` from the health helper. Check queue coverage
separately. For OTLP delivery, use the [OpenTelemetry package](otel.md).

## Install offline

Transfer the Windows ZIP, trusted `SHA256SUMS` file and installer through your
approved channel. Add these arguments to the installation command:

```powershell
-Archive 'D:\Media\mq-exporter-dist-v0.1.0-rc.1-windows-amd64.zip' `
-Checksums 'D:\Media\SHA256SUMS'
```

The version must match the archive. The installer verifies the checksum before
extraction and requires no GitHub token or development tools.

## Client connections and instances

For remote MQ, add `-Mode client -Channel APP.SVRCONN -ConnectionName
'mq.example.com(1414)'`. Check `Get-Help .\install.ps1 -Detailed` for the full
parameter list. Native MQ libraries remain required in client mode.

Each queue manager needs a distinct instance, such as `qm2`, and a distinct
Prometheus port, such as `9158`. Instance configuration and logs are independent.
The service adapter keeps the MQ library path local to its exporter process.

## Updates and service control

Run the installer with the new version and the existing instance identity.
It preserves configuration and existing service credentials. `-ReplaceConfig`
explicitly replaces configuration; identity changes also require `-Repoint`.
Existing binaries and replaced configuration have collision-safe backups.

The included `mq-service.exe` implements the Windows service protocol and retries
exporter exits after 15 seconds. It stops its tracked child on service stop.
The installer creates no MQ SERVICE object.

```powershell
Stop-Service mq-exporter-qm1
Start-Service mq-exporter-qm1
```

If an update fails after stopping the service, the service can remain stopped.
Inspect the error and backups before starting it. Arrange log rotation while the
service is stopped. Native Server 2019 install, upgrade, service-account,
stop/start and reboot checks have passed with the corrected rc.4 installer.
Live local-bindings and authenticated client tests also passed with the MQ
9.3.0.35 trial server. See [compatibility](compatibility.md) for the exact scope.
