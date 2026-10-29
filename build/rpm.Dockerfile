FROM registry.access.redhat.com/ubi8/ubi@sha256:018534b4e3bdc491de8b4dfd3b21662dba5c19fb24d11b8778d370de4d5e9eed
# Incident workaround until the distro ships a fixed CA package; public roots only.
COPY ca-blocklist/*.pem /etc/pki/ca-trust/source/blacklist/
COPY ca-blocklist/*.pem /etc/pki/ca-trust/source/blocklist/
RUN update-ca-trust
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
