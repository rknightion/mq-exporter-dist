import hashlib
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest


class ReleaseIndex(unittest.TestCase):
    def _prepare(self, root):
        (root / "build").mkdir()
        (root / "dist").mkdir()
        source = Path(__file__).resolve().parents[1] / "build"
        for name in ("release_index.py", "versions.py"):
            shutil.copyfile(source / name, root / "build" / name)
        return root / "build/release_index.py", root / "dist"

    def _write_archive(self, dist, name, data=b"synthetic", sha_override=None):
        archive = dist / name
        archive.write_bytes(data)
        sha = sha_override or hashlib.sha256(data).hexdigest()
        archive.with_name(archive.name + ".sha256").write_text(sha + "  " + archive.name + "\n")

    def test_complete_pairing_and_version(self):
        for case in ("valid", "missing", "mixed-version", "hash-mismatch"):
            with self.subTest(case=case), tempfile.TemporaryDirectory() as tmp:
                script, dist = self._prepare(Path(tmp))
                for product in ("mq-exporter-dist", "mq-otel-dist"):
                    for platform in ("linux-amd64.tar.gz", "windows-amd64.zip"):
                        last = product == "mq-otel-dist" and platform.endswith("zip")
                        if case == "missing" and last:
                            continue
                        version = "v0.1.0-rc.2" if case == "mixed-version" and last else "v0.1.0-rc.1"
                        name = product + "-" + version + "-" + platform
                        sha_override = "0" * 64 if case == "hash-mismatch" and last else None
                        self._write_archive(dist, name, sha_override=sha_override)
                result = subprocess.run(["python3", str(script)], capture_output=True)
                self.assertEqual(result.returncode == 0, case == "valid", result.stderr.decode())
                if case == "valid":
                    self.assertEqual(len((dist / "SHA256SUMS").read_text().splitlines()), 4)

    def test_native_release_accepts_revisioned_versions(self):
        with tempfile.TemporaryDirectory() as tmp:
            script, dist = self._prepare(Path(tmp))
            for product in ("mq-exporter-dist", "mq-otel-dist"):
                for platform in ("linux-amd64.tar.gz", "windows-amd64.zip"):
                    self._write_archive(dist, product + "-v6.0.0-1-rc.2-" + platform)
            result = subprocess.run(["python3", str(script)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual(len((dist / "SHA256SUMS").read_text().splitlines()), 4)

    def test_custom_release_is_exactly_one_linux_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            script, dist = self._prepare(Path(tmp))
            self._write_archive(dist, "mq-exporter-dist-custom-v0.1.0-custom-1-linux-amd64.tar.gz")
            result = subprocess.run(["python3", str(script)], capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr.decode())
            self.assertEqual(len((dist / "SHA256SUMS").read_text().splitlines()), 1)

    def test_custom_release_rejects_a_second_archive(self):
        with tempfile.TemporaryDirectory() as tmp:
            script, dist = self._prepare(Path(tmp))
            self._write_archive(dist, "mq-exporter-dist-custom-v0.1.0-custom-1-linux-amd64.tar.gz")
            self._write_archive(dist, "mq-exporter-dist-custom-v0.1.0-custom-1-windows-amd64.zip")
            result = subprocess.run(["python3", str(script)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)

    def test_mixed_tracks_is_an_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            script, dist = self._prepare(Path(tmp))
            for product in ("mq-exporter-dist", "mq-otel-dist"):
                for platform in ("linux-amd64.tar.gz", "windows-amd64.zip"):
                    self._write_archive(dist, product + "-v0.1.0-1-" + platform)
            self._write_archive(dist, "mq-exporter-dist-custom-v0.1.0-custom-1-linux-amd64.tar.gz")
            result = subprocess.run(["python3", str(script)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)

    def test_unrecognised_archive_name_is_an_error(self):
        with tempfile.TemporaryDirectory() as tmp:
            script, dist = self._prepare(Path(tmp))
            self._write_archive(dist, "mq-exporter-dist-not-a-version-linux-amd64.tar.gz")
            result = subprocess.run(["python3", str(script)], capture_output=True)
            self.assertNotEqual(result.returncode, 0)


if __name__ == "__main__":
    unittest.main()
