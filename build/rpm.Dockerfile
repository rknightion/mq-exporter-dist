FROM registry.access.redhat.com/ubi8/ubi@sha256:193e722c0c5df1f7e68e2c93cb73fcd6b8529221829f89ab5f6f3deab62fbfaa
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
