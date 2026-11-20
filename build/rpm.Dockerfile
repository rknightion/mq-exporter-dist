FROM registry.access.redhat.com/ubi8/ubi@sha256:0373571b7a71fbf646b735fda77818d033e9cfd221eaed3a769ab6f1a1e56277
# Incident workaround until the distro ships a fixed CA package; public roots only.
COPY ca-blocklist/*.pem /etc/pki/ca-trust/source/blacklist/
COPY ca-blocklist/*.pem /etc/pki/ca-trust/source/blocklist/
RUN update-ca-trust
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
