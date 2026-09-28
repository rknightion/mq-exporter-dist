FROM registry.access.redhat.com/ubi8/ubi@sha256:f697c36afadf6eef96d24c4b2428f165fcea7029a6f7733c01444505f2bac203
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
