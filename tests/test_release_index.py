import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class ReleaseIndex(unittest.TestCase):
    def test_complete_pairing_and_version(self):
        for case in ("valid", "missing", "mixed-version", "hash-mismatch"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmp:
                root = Path(tmp)
                (root / "build").mkdir()
                (root / "dist").mkdir()
                script = root / "build/release_index.py"
                shutil.copyfile(Path(__file__).resolve().parents[1] / "build/release_index.py", script)
                for product in ("mq-exporter-dist", "mq-otel-dist"):
                    for platform in ("linux-amd64.tar.gz", "windows-amd64.zip"):
                        last = product == "mq-otel-dist" and platform.endswith("zip")
                        if case == "missing" and last:
                            continue
                        version = "v0.1.0-rc.2" if case == "mixed-version" and last else "v0.1.0-rc.1"
                        archive = root / "dist" / (product + "-" + version + "-" + platform)
                        archive.write_bytes(b"synthetic")
                        sha = "0" * 64 if case == "hash-mismatch" and last else hashlib.sha256(b"synthetic").hexdigest()
                        archive.with_name(archive.name + ".sha256").write_text(sha + "  " + archive.name + "\n")
                result = subprocess.run(["python3", str(script)], capture_output=True)
                self.assertEqual(result.returncode == 0, case == "valid", result.stderr.decode())
                if case == "valid":
                    self.assertEqual(len((root / "dist/SHA256SUMS").read_text().splitlines()), 4)
