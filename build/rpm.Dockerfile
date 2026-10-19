FROM registry.access.redhat.com/ubi8/ubi@sha256:70bb51215d4452426d434aed707a297c7e03cbe551e910d6b9aa0fa39cd26edc
# Packaging only: no MQ runtime/SDK and no collector rebuild.
ARG RPM_BUILD_VERSION
RUN test -n "$RPM_BUILD_VERSION" && LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install "rpm-build-$RPM_BUILD_VERSION" \
    && dnf clean all
