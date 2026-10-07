FROM registry.access.redhat.com/ubi8/ubi@sha256:0d301773f08b9d43e8d499472f499da00d3e52f0e0b54b245f8c70cf0708b512
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
