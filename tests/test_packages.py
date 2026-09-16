"""Package separation is a public download/install contract."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "build"))
import build


class Packages(unittest.TestCase):
    def test_separate_payload_and_installer_defaults(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "LICENSE").write_text("synthetic license")
            shutil.copytree(ROOT / "install", root / "install")
            source = root / "upstream"
            (source / "vendor").mkdir(parents=True)
            (source / "LICENSE").write_text("synthetic upstream license")
            (source / "vendor/modules.txt").write_text("")
            output = root / "output"
            output.mkdir()
            for name in ("mq_prometheus", "mq_otel", "mq-dist", "mq-config-check"):
                (output / name).write_bytes(b"synthetic binary")
            for exporter, other in (("prometheus", "otel"), ("otel", "prometheus")):
                with patch.object(build, "ROOT", root):
                    archive = build.package(source, output, "v0.1.0-rc.9", "linux-amd64", "a" * 40, {}, exporter)
                with tarfile.open(archive) as payload:
                    self.assertIn("mq_" + exporter, payload.getnames())
                    self.assertNotIn("mq_" + other, payload.getnames())
                    self.assertEqual(len(payload.getnames()), 9)
                    installer = payload.extractfile("install.sh").read().decode()
                    self.assertIn("exporter=" + exporter + " # package default", installer)
                    self.assertEqual(json.load(payload.extractfile("build-metadata.json"))["exporter"], exporter)
                for requested, success in ((exporter, True), (other, False)):
                    # Give the wrong selector a matching checksum filename too;
                    # rejection must check the payload, not just its filename.
                    prefix = "mq-exporter-dist" if requested == "prometheus" else "mq-otel-dist"
                    sums = root / "SHA256SUMS"
                    sums.write_text(hashlib.sha256(archive.read_bytes()).hexdigest() + "  " + prefix + "-v0.1.0-rc.9-linux-amd64.tar.gz\n")
                    result = subprocess.run(["bash", str(ROOT / "install/install.sh"), "--verify-archive", str(archive), str(sums), "v0.1.0-rc.9", requested], capture_output=True)
                    self.assertEqual(result.returncode == 0, success, result.stderr.decode())
