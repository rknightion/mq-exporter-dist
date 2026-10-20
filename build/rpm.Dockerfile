FROM registry.access.redhat.com/ubi8/ubi@sha256:c0fd81a16789aceea2f12b6644ac0f1a743ba4632414211ed76ef10adf196452
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
