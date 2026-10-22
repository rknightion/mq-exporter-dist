FROM registry.access.redhat.com/ubi8/ubi@sha256:55ee9ba821ddaff96cdcd28c9c5482ca46091bdb150166515bf0fc4e5459b287
# Incident workaround until the distro ships a fixed CA package; public roots only.
COPY build/ca-blocklist/*.pem /etc/pki/ca-trust/source/blacklist/
COPY build/ca-blocklist/*.pem /etc/pki/ca-trust/source/blocklist/
RUN update-ca-trust
# This image contains no MQ SDK or runtime. Never publish an image with MQ inputs.
RUN LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install \
    gcc-8.5.0-29.el8_10 binutils-2.30-128.el8_10 \
    glibc-devel-2.28-251.el8_10.48 diffutils-3.6-6.el8 \
    && dnf clean all
ENV GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off GOOS=linux GOARCH=amd64 GOAMD64=v1 CGO_ENABLED=1
ENV PATH=/opt/go/bin:/usr/bin:/bin
ENV CGO_CFLAGS="-O2 -march=x86-64 -mtune=generic -ffile-prefix-map=/work=."
ENV CGO_LDFLAGS="-Wl,--enable-new-dtags"
WORKDIR /work/upstream
