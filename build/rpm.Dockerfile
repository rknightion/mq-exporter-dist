FROM registry.access.redhat.com/ubi8/ubi@sha256:91e8320e4a77e25b086b70d534cd15dd3b404d23fb1a7e6fd5dc0d8274fc9926
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
