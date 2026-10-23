FROM registry.access.redhat.com/ubi8/ubi@sha256:04f1f054df24a55ea46e84b9a9dd83f4bb7e3bdbb0276d07d7b735803933d3bd
# Incident workaround until the distro ships a fixed CA package; public roots only.
COPY ca-blocklist/*.pem /etc/pki/ca-trust/source/blacklist/
COPY ca-blocklist/*.pem /etc/pki/ca-trust/source/blocklist/
RUN update-ca-trust
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
