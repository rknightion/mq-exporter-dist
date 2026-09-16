import hashlib
from pathlib import Path

dist = Path(__file__).resolve().parents[1] / "dist"
archives = sorted([*dist.glob("*.tar.gz"), *dist.glob("*.zip")])
linux = list(dist.glob('mq-exporter-dist-*-linux-amd64.tar.gz'))
windows = list(dist.glob('mq-exporter-dist-*-windows-amd64.zip'))
if len(archives) != 2 or len(linux) != 1 or len(windows) != 1:
    raise SystemExit("exactly one Linux archive and one Windows archive required")
versions = {p.name.split("-linux-amd64")[0].split("-windows-amd64")[0] for p in archives}
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
