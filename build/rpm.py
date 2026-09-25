"""Wrap verified candidate bytes in separate RPMs; never compile upstream here."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tarfile
import tempfile

from public_check import inspect
import versions

ROOT = Path(__file__).resolve().parents[1]


def publish_bundle(target, rpm_bytes, evidence):
    """Exclusive publication; RPM last marks a complete bundle. Never overwrite."""
    sha = hashlib.sha256(rpm_bytes).hexdigest()
    evidence["rpm_sha256"] = sha
    files = {target.name + ".sha256": (sha + "  " + target.name + "\n").encode(),
             target.name + ".metadata.json": (json.dumps(evidence, indent=2, sort_keys=True) + "\n").encode(),
             target.name: rpm_bytes}
    lock = target.with_name(target.name + ".lock")
    lock.mkdir()
    created = []
    try:
        if any((target.parent / name).exists() or (target.parent / name).is_symlink() for name in files):
            raise ValueError("refusing to overwrite existing package or sidecar")
        with tempfile.TemporaryDirectory(prefix=".rpm-stage-", dir=target.parent) as tmp:
            for name, data in files.items():
                staged = Path(tmp) / name
                with staged.open("xb") as stream:
                    stream.write(data)
                    stream.flush()
                    os.fsync(stream.fileno())
            try:
                for name in files:  # Package is last, after its verified sidecars.
                    source = Path(tmp) / name
                    destination = target.parent / name
                    os.link(source, destination)
                    created.append((destination, source.stat()))
            except BaseException:
                for destination, owned in reversed(created):
                    if destination.exists():
                        current = destination.lstat()
                        if (current.st_dev, current.st_ino) == (owned.st_dev, owned.st_ino):
                            destination.unlink()
                raise
    finally:
        lock.rmdir()


def rpm_version(tag, distribution):
    if not re.fullmatch(r"v[0-9]+\.[0-9]+\.[0-9]+", tag):
        raise ValueError("upstream must be an exact release tag")
    version = versions.parse(distribution)
    if version.track != "native":
        raise ValueError("RPM packaging is native-only")
    if version.upstream_tag != tag:
        raise ValueError("distribution upstream must equal the release tag")
    release = version.upstream
    if version.revision:
        release += "_" + str(version.revision)
    if version.rc is not None:
        release += "~rc." + str(version.rc)
    return version.upstream, release + ".mqdist"


def verified_payload(archive, checksums):
    expected = [line.split()[0] for line in checksums.read_text().splitlines()
                if len(line.split()) == 2 and line.split()[1] == archive.name]
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if expected != [digest]:
        raise ValueError("missing, duplicate or mismatched archive checksum")
    with tarfile.open(archive) as tar:
        members = tar.getmembers()
        if len(members) not in (9, 11) or any(not m.isfile() or m.size > 128 * 1024 * 1024 for m in members):
            raise ValueError("unsafe archive member/count")
        names = [m.name for m in members]
        if len(set(names)) != len(names):
            raise ValueError("duplicate archive member names")
        common = {"mq-dist", "mq-config-check", "install.sh", "diagnose.sh", "LICENSE",
                  "THIRD-PARTY-NOTICES.txt", "build-metadata.json", "sbom.cdx.json"}
        extended = common | {"update.sh", "known-releases.json"}
        native = [common | {"mq_prometheus"}, common | {"mq_otel"},
                  extended | {"mq_prometheus"}, extended | {"mq_otel"}]
        if set(names) not in native:
            raise ValueError("unexpected, duplicate or custom-track payload paths")
        payload = {m.name: tar.extractfile(m).read() for m in members}
    for name, data in payload.items():
        inspect(data, name)
    metadata = json.loads(payload["build-metadata.json"])
    exporter = metadata["exporter"]
    if exporter not in ("prometheus", "otel") or "mq_" + exporter not in payload or metadata["platform"] != "linux-amd64":
        raise ValueError("archive identity mismatch")
    for name, data in payload.items():
        if name != "build-metadata.json" and metadata["payload_sha256"].get(name) != hashlib.sha256(data).hexdigest():
            raise ValueError("payload metadata mismatch")
    return payload, metadata, digest


def unit(name, exporter):
    return f"""[Unit]
Description=Community IBM MQ {exporter} exporter instance %i
After=network-online.target
Wants=network-online.target
StartLimitIntervalSec=0
ConditionPathExists=/etc/{name}/%i.json

[Service]
Type=simple
User=mqmon
ExecStart=/usr/libexec/{name}/mq_{exporter} -f /etc/{name}/%i.json
Environment="LD_LIBRARY_PATH=/opt/mqm/lib64:/usr/lib64:/lib64"
Restart=on-failure
RestartSec=15s
UMask=0077
NoNewPrivileges=true
ProtectSystem=strict
ReadWritePaths=-/var/mqm
ProtectHome=true
PrivateTmp=false

[Install]
WantedBy=multi-user.target
"""


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("archive", type=Path)
    parser.add_argument("checksums", type=Path)
    parser.add_argument("--output", type=Path, default=ROOT / ".work/rpm-candidates")
    args = parser.parse_args()
    payload, metadata, digest = verified_payload(args.archive, args.checksums)
    version, release = rpm_version(metadata["inputs"]["upstream_tag"], metadata["distribution_version"])
    exporter = metadata["exporter"]
    name = "mq-prometheus" if exporter == "prometheus" else "mq-otel"
    args.output.mkdir(parents=True, exist_ok=True)
    target = args.output / f"{name}-{version}-{release}.x86_64.rpm"
    if target.exists():
        raise ValueError("refusing to overwrite an existing package")
    rpm_tool = subprocess.check_output(["just", "--evaluate", "rpm_build_version"], cwd=ROOT, text=True).strip().strip('"')
    subprocess.run(["docker", "build", "--platform", "linux/amd64", "--build-arg", "RPM_BUILD_VERSION=" + rpm_tool, "-f", str(ROOT / "build/rpm.Dockerfile"),
                    "-t", "mq-dist-rpm-build", str(ROOT / "build")], check=True)
    image = subprocess.check_output(["docker", "image", "inspect", "mq-dist-rpm-build", "--format", "{{.Id}}"], text=True).strip()
    (ROOT / ".work").mkdir(exist_ok=True)
    with tempfile.TemporaryDirectory(prefix="rpm-", dir=ROOT / ".work") as tmp:
        work = Path(tmp)
        (work / "payload").mkdir()
        for filename, data in payload.items():
            (work / "payload" / filename).write_bytes(data)
        spec = (ROOT / "build/rpm.spec.in").read_text()
        for key, value in {"NAME": name, "VERSION": version, "RELEASE": release, "EXPORTER": exporter}.items():
            spec = spec.replace("@" + key + "@", value)
        (work / "package.spec").write_text(spec)
        (work / "instance.service").write_text(unit(name, exporter))
        epoch = subprocess.check_output(["git", "show", "-s", "--format=%ct", "HEAD"], cwd=ROOT, text=True).strip()
        command = ["docker", "run", "--rm", "--platform", "linux/amd64", "--network=none",
                   "--user", f"{os.getuid()}:{os.getgid()}",
                   "-v", str(work) + ":/work", "-e", "SOURCE_DATE_EPOCH=" + epoch, image]
        subprocess.run(command + ["rpmbuild", "-bb", "--define", "_topdir /work/rpmbuild",
                                 "--define", "_buildhost reproducible.invalid", "--define", "use_source_date_epoch_as_buildtime 1",
                                 "--define", "clamp_mtime_to_source_date_epoch 1", "/work/package.spec"], check=True)
        built = work / "rpmbuild/RPMS/x86_64" / target.name
        requirements = subprocess.check_output(command + ["rpm", "-qp", "--requires", "/work/rpmbuild/RPMS/x86_64/" + target.name], text=True)
        tooling = subprocess.check_output(command + ["rpm", "-qa", "--qf", "%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n"], text=True)
        # Decode the actual RPM payload and scan it before releasing any bytes.
        subprocess.run(command + ["bash", "-euo", "pipefail", "-c",
                                 'mkdir /work/unpacked; cd /work/unpacked; rpm2cpio /work/rpmbuild/RPMS/x86_64/*.rpm | cpio -idm --quiet --no-preserve-owner'], check=True)
        for path in (work / "unpacked").rglob("*"):
            if path.is_symlink():
                raise ValueError("unexpected RPM link")
            if path.is_file():
                inspect(path.read_bytes(), str(path.relative_to(work / "unpacked")))
        for binary in ("mq_" + exporter, "mq-dist", "mq-config-check"):
            if (work / "unpacked/usr/libexec" / name / binary).read_bytes() != payload[binary]:
                raise ValueError("RPM modified tested executable bytes")
        rpm_bytes = built.read_bytes()
    evidence = {"rpm_version": version, "rpm_release": release, "archive_sha256": digest,
                "source": metadata, "packaging_commit": subprocess.check_output(
                    ["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip(),
                "packaging_image": image, "rpm_inventory": tooling.splitlines(), "requires": requirements.splitlines(),
                "packaging_dirty": bool(subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT)),
                "packaging_inputs_sha256": {p: hashlib.sha256((ROOT / p).read_bytes()).hexdigest()
                                            for p in ("build/rpm.py", "build/rpm.spec.in", "build/rpm.Dockerfile", "justfile")},
                "binary_identity": "identical to input archive", "signed": False,
                "native_install_selinux_lifecycle": "not tested"}
    publish_bundle(target, rpm_bytes, evidence)
    print(target)


if __name__ == "__main__":
    main()
