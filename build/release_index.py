import hashlib
import re
from pathlib import Path

dist = Path(__file__).resolve().parents[1] / "dist"
archives = sorted([*dist.glob("*.tar.gz"), *dist.glob("*.zip")])
matches = [re.fullmatch(r'(mq-exporter-dist|mq-otel-dist)-(v\d+\.\d+\.\d+(?:-rc\.\d+)?)-(linux-amd64\.tar\.gz|windows-amd64\.zip)', p.name) for p in archives]
if len(archives) != 4 or not all(matches):
    raise SystemExit("one Linux and Windows archive for each exporter required")
if len({(m[1], m[3]) for m in matches}) != 4:
    raise SystemExit("duplicate exporter/platform pair")
versions = {m[2] for m in matches}
if len(versions) != 1:
    raise SystemExit("mixed release versions")
lines = []
for p in archives:
    sha = hashlib.sha256(p.read_bytes()).hexdigest()
    recorded = p.with_name(p.name + ".sha256").read_text()
    if recorded != sha + "  " + p.name + "\n":
        raise SystemExit("tested archive hash mismatch")
    lines.append(recorded)
(dist / "SHA256SUMS").write_text("".join(lines))
