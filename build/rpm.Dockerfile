FROM registry.access.redhat.com/ubi8/ubi@sha256:b40af4457b2a8b8425be9887d70ba47c100c3ba0d9fd2aa77c974e7e08c5f66f
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
