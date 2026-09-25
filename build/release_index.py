import hashlib
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parent))
import versions

ROOT = Path(__file__).resolve().parents[1]
DIST = ROOT / "dist"

# Ordered longest-prefix-first so "mq-exporter-dist-custom" is tried before
# the "mq-exporter-dist" prefix it also starts with.
PRODUCTS = ("mq-exporter-dist-custom", "mq-exporter-dist", "mq-otel-dist")
PLATFORMS = ("linux-amd64.tar.gz", "windows-amd64.zip")


def classify(archive):
    for product in PRODUCTS:
        prefix = product + "-"
        if not archive.name.startswith(prefix):
            continue
        remainder = archive.name[len(prefix):]
        for platform in PLATFORMS:
            suffix = "-" + platform
            if not remainder.endswith(suffix):
                continue
            version_text = remainder[:-len(suffix)]
            try:
                version = versions.parse(version_text)
            except ValueError:
                continue
            return product, platform, version
    return None


def main():
    archives = sorted([*DIST.glob("*.tar.gz"), *DIST.glob("*.zip")])
    classified = [(archive, classify(archive)) for archive in archives]
    if not classified or any(c is None for _, c in classified):
        raise SystemExit("unrecognised release archive name")
    tracks = {c[2].track for _, c in classified}
    if len(tracks) != 1:
        raise SystemExit("mixed native and custom archives")
    track = tracks.pop()
    if track == "native":
        products = {c[0] for _, c in classified}
        pairs = {(c[0], c[1]) for _, c in classified}
        if len(classified) != 4 or products != {"mq-exporter-dist", "mq-otel-dist"} or len(pairs) != 4:
            raise SystemExit("one Linux and Windows archive for each exporter required")
    else:
        if len(classified) != 1 or classified[0][1][:2] != ("mq-exporter-dist-custom", "linux-amd64.tar.gz"):
            raise SystemExit("custom release must be exactly one Linux archive")
    versions_seen = {c[2].text for _, c in classified}
    if len(versions_seen) != 1:
        raise SystemExit("mixed release versions")
    lines = []
    for archive, _ in classified:
        sha = hashlib.sha256(archive.read_bytes()).hexdigest()
        recorded = archive.with_name(archive.name + ".sha256").read_text()
        if recorded != sha + "  " + archive.name + "\n":
            raise SystemExit("tested archive hash mismatch")
        lines.append(recorded)
    (DIST / "SHA256SUMS").write_text("".join(lines))


if __name__ == "__main__":
    main()
