FROM registry.access.redhat.com/ubi8/ubi@sha256:510b852959656e2d591941e6df9b2a5c71031717ccef036ae35f46db0d039cce
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
