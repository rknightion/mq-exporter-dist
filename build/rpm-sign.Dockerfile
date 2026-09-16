FROM almalinux:10@sha256:957738702313e6ee452cdb17bc1431542c467be9a4e2f4da3b8e551b0ebb9677
# Signing tools only. This image never contains MQ files or private keys.
ARG RPM_SIGN_VERSION
ARG CREATEREPO_VERSION
RUN test -n "$RPM_SIGN_VERSION" && test -n "$CREATEREPO_VERSION" \
    && dnf -y --disablerepo='*' \
       --repofrompath=sign-base,https://repo.almalinux.org/almalinux/9/BaseOS/x86_64/os/ \
       --repofrompath=sign-app,https://repo.almalinux.org/almalinux/9/AppStream/x86_64/os/ \
       --setopt=sign-base.gpgcheck=1 --setopt=sign-app.gpgcheck=1 \
       --setopt=sign-base.gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-9 \
       --setopt=sign-app.gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-AlmaLinux-9 \
       install "rpm-sign-$RPM_SIGN_VERSION" "createrepo_c-$CREATEREPO_VERSION" \
    && dnf clean all
