# escape=`
# Disposable test image only. MQ SDK and exporter files are mounted at runtime.
FROM mcr.microsoft.com/windows/servercore@sha256:bea74690d808bba3e6b0d4ba4c599305aea1f66c875f133f1e75855841dcb1d5
ARG INSTALL_USER=ContainerAdministrator
USER ${INSTALL_USER}
COPY vc_redist.x64.exe C:/prerequisites/vc_redist.x64.exe
COPY install-runtime.ps1 C:/prerequisites/install-runtime.ps1
RUN powershell.exe -NoLogo -NoProfile -NonInteractive -File C:\prerequisites\install-runtime.ps1
USER ContainerAdministrator
