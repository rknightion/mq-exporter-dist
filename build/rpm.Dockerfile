FROM registry.access.redhat.com/ubi8/ubi@sha256:5868426b49c3db5e0e6b14daead8e7d853f4c0bece0d8f7a87671f8db4d03858
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
