"""Revise distribution packaging while retaining an accepted release's executables."""

import argparse
import gzip
import hashlib
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile
import zipfile

import versions


ROOT = Path(__file__).resolve().parents[1]
RELEASES = "https://github.com/rknightion/mq-exporter-dist/releases/download"


def digest(data):
    return hashlib.sha256(data).hexdigest()


def download(version, name):
    result = subprocess.run(
        ["curl", "--fail", "--silent", "--show-error", "--location", "--proto", "=https",
         "--proto-redir", "=https", "--retry", "3", "--max-time", "900",
         f"{RELEASES}/{version}/{name}"],
        check=True, stdout=subprocess.PIPE,
    )
    return result.stdout


def members(archive, platform):
    payload = {}
    if platform == "windows-amd64":
        with zipfile.ZipFile(io.BytesIO(archive)) as source:
            for entry in source.infolist():
                if entry.is_dir() or entry.filename in payload or "/" in entry.filename or "\\" in entry.filename:
                    raise ValueError("unsafe or duplicate source archive member")
                payload[entry.filename] = source.read(entry)
    else:
        with tarfile.open(fileobj=io.BytesIO(archive), mode="r:gz") as source:
            for entry in source:
                if not entry.isfile() or entry.name in payload or "/" in entry.name or "\\" in entry.name:
                    raise ValueError("unsafe or duplicate source archive member")
                payload[entry.name] = source.extractfile(entry).read()
    return payload


def archive_bytes(payload, platform, binary):
    output = io.BytesIO()
    if platform == "windows-amd64":
        with zipfile.ZipFile(output, "w", zipfile.ZIP_DEFLATED, compresslevel=9) as target:
            for name, data in sorted(payload.items()):
                entry = zipfile.ZipInfo(name, (2026, 1, 1, 0, 0, 0))
                entry.external_attr = 0o100644 << 16
                entry.compress_type = zipfile.ZIP_DEFLATED
                target.writestr(entry, data)
    else:
        with gzip.GzipFile(filename="", mode="wb", fileobj=output, mtime=0) as compressed:
            with tarfile.open(fileobj=compressed, mode="w", format=tarfile.USTAR_FORMAT) as target:
                for name, data in sorted(payload.items()):
                    entry = tarfile.TarInfo(name)
                    entry.size = len(data)
                    entry.mode = 0o755 if name in (binary, "mq-config-check", "mq-dist", "install.sh", "diagnose.sh", "update.sh") else 0o644
                    target.addfile(entry, io.BytesIO(data))
    return output.getvalue()


def revise(version, source_version, platform, exporter):
    target_version = versions.parse(version)
    base_version = versions.parse(source_version)
    if target_version.track != base_version.track or target_version.upstream_tag != base_version.upstream_tag:
        raise ValueError("source and target must share the upstream version and track")
    if target_version.track == "custom" and (platform != "linux-amd64" or exporter != "prometheus"):
        raise ValueError("custom releases support Linux Prometheus only")
    if source_version == version:
        raise ValueError("source and target releases must differ")
    if subprocess.check_output(["git", "status", "--porcelain"], cwd=ROOT).strip():
        raise ValueError("commit and review distribution changes before revising release bytes")
    commit = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
    prefix = "mq-otel-dist" if exporter == "otel" else "mq-exporter-dist"
    binary = "mq_otel" if exporter == "otel" else "mq_prometheus"
    if target_version.track == "custom":
        prefix += "-custom"
        binary = "mq_prometheus_custom"
    extension = ".zip" if platform == "windows-amd64" else ".tar.gz"
    source_name = f"{prefix}-{source_version}-{platform}{extension}"
    target_name = f"{prefix}-{version}-{platform}{extension}"
    sums = download(source_version, "SHA256SUMS").decode().splitlines()
    expected = [line.split()[0] for line in sums if len(line.split()) == 2 and line.split()[1] == source_name]
    if len(expected) != 1 or not re.fullmatch(r"[0-9a-f]{64}", expected[0]):
        raise ValueError("source archive checksum missing or duplicated")
    source_archive = download(source_version, source_name)
    if digest(source_archive) != expected[0]:
        raise ValueError("source archive checksum mismatch")
    payload = members(source_archive, platform)
    metadata = json.loads(payload["build-metadata.json"])
    if (metadata["distribution_version"], metadata["platform"], metadata["exporter"], metadata["track"]) != (
        source_version, platform, exporter, target_version.track
    ):
        raise ValueError("source archive metadata mismatch")
    actual = {name: digest(data) for name, data in payload.items() if name != "build-metadata.json"}
    known = json.loads((ROOT / "build" / "known-releases.json").read_text())
    accepted = [item for item in known if item["tag"] == source_version and item["platform"] == platform and item["exporter"] == exporter]
    if actual != metadata["payload_sha256"] or len(accepted) != 1 or actual != accepted[0]["payload_sha256"]:
        raise ValueError("source payload differs from the accepted release inventory")
    if platform == "linux-amd64":
        installer = (ROOT / "install" / "install.sh").read_text()
        payload["install.sh"] = installer.replace("exporter=prometheus # package default", f"exporter={exporter} # package default").encode()
    sbom = json.loads(payload["sbom.cdx.json"])
    sbom["metadata"]["component"]["version"] = version
    payload["sbom.cdx.json"] = json.dumps(sbom, indent=2, sort_keys=True).encode()
    metadata["distribution_version"] = version
    metadata["distribution_commit"] = commit
    metadata["repackaged_from"] = {"release": source_version, "archive_sha256": expected[0]}
    metadata["payload_sha256"] = {name: digest(data) for name, data in payload.items() if name != "build-metadata.json"}
    changed = {name for name in actual if actual[name] != metadata["payload_sha256"][name]}
    allowed = {"install.sh", "sbom.cdx.json"} if platform == "linux-amd64" else {"sbom.cdx.json"}
    if changed != allowed:
        raise ValueError("unexpected source payload change: " + ", ".join(sorted(changed)))
    payload["build-metadata.json"] = json.dumps(metadata, indent=2, sort_keys=True).encode()
    output = ROOT / "dist"
    output.mkdir(exist_ok=True)
    target = output / target_name
    if target.exists():
        raise ValueError("target archive already exists")
    data = archive_bytes(payload, platform, binary)
    target.write_bytes(data)
    (output / (target_name + ".sha256")).write_bytes((digest(data) + "  " + target_name + "\n").encode())
    (output / (target_name + ".metadata.json")).write_bytes(payload["build-metadata.json"])
    (output / (target_name + ".sbom.cdx.json")).write_bytes(payload["sbom.cdx.json"])
    print(target_name + " sha256=" + digest(data))


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("version")
    parser.add_argument("source_version")
    parser.add_argument("platform", choices=("linux-amd64", "windows-amd64"))
    parser.add_argument("exporter", choices=("prometheus", "otel"))
    arguments = parser.parse_args()
    revise(arguments.version, arguments.source_version, arguments.platform, arguments.exporter)


if __name__ == "__main__":
    main()
