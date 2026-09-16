ARG BASE
FROM ${BASE}
RUN LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install policycoreutils \
    && dnf clean all
