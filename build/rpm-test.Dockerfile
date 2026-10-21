ARG BASE
FROM ${BASE}
# Incident workaround until the distro ships a fixed CA package; public roots only.
COPY ca-blocklist/*.pem /etc/pki/ca-trust/source/blacklist/
COPY ca-blocklist/*.pem /etc/pki/ca-trust/source/blocklist/
RUN update-ca-trust
RUN LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install policycoreutils \
    && dnf clean all
