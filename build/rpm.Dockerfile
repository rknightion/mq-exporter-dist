FROM registry.access.redhat.com/ubi8/ubi@sha256:0251a8aae836408233eee58dbd3a9b1659efe479b9060a4704161526ff85d329
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
