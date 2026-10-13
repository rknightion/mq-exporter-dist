FROM registry.access.redhat.com/ubi8/ubi@sha256:605201f8ae4671e95cee47fbb1a436f4de992e487357dea61793bff97ff9de1c
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
