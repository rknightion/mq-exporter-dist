FROM registry.access.redhat.com/ubi8/ubi@sha256:a86524e44e6529a8890b93eb73341a4fe4c70ec3da442bbfd86a8b64a1fc2359
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
