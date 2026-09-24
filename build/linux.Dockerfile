FROM registry.access.redhat.com/ubi8/ubi@sha256:45efff79b3a5b35b21f8df8ac108b8ac615c27396d1448195e7ed01ebbf0a903
# This image contains no MQ SDK or runtime. Never publish an image with MQ inputs.
RUN LD_LIBRARY_PATH=/usr/lib64:/lib64 dnf -y install \
    gcc-8.5.0-28.el8_10 binutils-2.30-128.el8_10 \
    glibc-devel-2.28-251.el8_10.40 diffutils-3.6-6.el8 \
    && dnf clean all
ENV GOTOOLCHAIN=local GOPROXY=off GOSUMDB=off GOOS=linux GOARCH=amd64 GOAMD64=v1 CGO_ENABLED=1
ENV PATH=/opt/go/bin:/usr/bin:/bin
ENV CGO_CFLAGS="-O2 -march=x86-64 -mtune=generic -ffile-prefix-map=/work=."
ENV CGO_LDFLAGS="-Wl,--enable-new-dtags"
WORKDIR /work/upstream
