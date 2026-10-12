FROM registry.access.redhat.com/ubi8/ubi@sha256:fde7a3bd1de511d4eeb5f3ebf0449b88352c730761a8159f8669d3394638d3c2
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
