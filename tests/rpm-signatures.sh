#!/usr/bin/env bash
# Trust and DNF transactions inside a disposable userspace, not native service proof.
set -euo pipefail
[[ -e /.dockerenv && ${MQ_DIST_RPM_TEST:-} == 1 ]] || exit 1
cmp /project/keys/RPM-GPG-KEY-mq-exporter-dist /packages/RPM-GPG-KEY-mq-exporter-dist
scratch=$(mktemp -d)
mkdir -m700 "$scratch/gpg" "$scratch/rpmdb"
gpg2 --homedir "$scratch/gpg" --batch --import /project/keys/RPM-GPG-KEY-mq-exporter-dist
gpg2 --homedir "$scratch/gpg" --batch --verify /packages/SHA256SUMS.asc /packages/SHA256SUMS
gpg2 --homedir "$scratch/gpg" --batch --verify /packages/repodata/repomd.xml.asc /packages/repodata/repomd.xml
cp /packages/repodata/repomd.xml "$scratch/repomd.xml"
printf '\n' >> "$scratch/repomd.xml"
if gpg2 --homedir "$scratch/gpg" --batch --verify /packages/repodata/repomd.xml.asc "$scratch/repomd.xml"; then
    echo 'ERROR: modified repository metadata passed verification' >&2
    exit 1
fi
(cd /packages && sha256sum --check SHA256SUMS)
rpm --dbpath "$scratch/rpmdb" --initdb
for package in /packages/*.rpm; do
    # No-key must fail: digest-only verification is not signature verification.
    if rpmkeys --dbpath "$scratch/rpmdb" --checksig "$package"; then
        echo 'ERROR: package verified without the signing key' >&2
        exit 1
    fi
done
rpmkeys --dbpath "$scratch/rpmdb" --import /project/keys/RPM-GPG-KEY-mq-exporter-dist
for package in /packages/*.rpm; do
    rpmkeys --dbpath "$scratch/rpmdb" --checksig --verbose "$package" > "$scratch/check"
    grep -E 'RSA/SHA256 Signature.*: OK$' "$scratch/check"
    cat "$scratch/check"
    cp "$package" "$scratch/corrupt.rpm"
    offset=$(( $(stat -c '%s' "$package") - 1 ))
    original=$(od -An -tu1 -j"$offset" -N1 "$package")
    printf -v changed '\\%03o' "$((original ^ 1))"
    printf '%b' "$changed" | dd of="$scratch/corrupt.rpm" bs=1 seek="$offset" conv=notrunc status=none
    if rpmkeys --dbpath "$scratch/rpmdb" --checksig "$scratch/corrupt.rpm"; then
        echo 'ERROR: corrupt package passed verification' >&2
        exit 1
    fi
done
mv /usr/bin/systemctl /usr/bin/systemctl.rpm-test-original
install -m755 /project/tests/rpm-systemctl.sh /usr/bin/systemctl
dnf -y --disablerepo='*' --repofrompath=mq,file:///packages \
    --setopt=mq.gpgcheck=1 --setopt=mq.repo_gpgcheck=1 \
    --setopt=mq.gpgkey=file:///project/keys/RPM-GPG-KEY-mq-exporter-dist \
    install mq-prometheus mq-otel
test -x /usr/libexec/mq-prometheus/mq_prometheus
test -x /usr/libexec/mq-otel/mq_otel
if grep -E 'start|enable|preset' /tmp/rpm-systemctl-calls; then exit 1; fi
echo 'PASS: RPM signatures, tamper rejection, signed repository metadata and strict DNF install'
