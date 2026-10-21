# escape=`
# Disposable test image only. MQ SDK and exporter files are mounted at runtime.
FROM mcr.microsoft.com/windows/servercore:ltsc2019@sha256:849b93b10aab37706b3d38df598973b2d1811bc3b818147baf4a342e0a9f73cf
# The bootstrapper's elevation handoff stalls under ContainerAdministrator.
# Use container-local SYSTEM for installation only, not for exporter tests.
USER "NT AUTHORITY\SYSTEM"
COPY vc_redist.x64.exe C:/prerequisites/vc_redist.x64.exe
COPY install-runtime.ps1 C:/prerequisites/install-runtime.ps1
RUN powershell.exe -NoLogo -NoProfile -NonInteractive -File C:\prerequisites\install-runtime.ps1
USER ContainerAdministrator
