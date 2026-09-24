FROM registry.access.redhat.com/ubi8/ubi@sha256:45efff79b3a5b35b21f8df8ac108b8ac615c27396d1448195e7ed01ebbf0a903
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
