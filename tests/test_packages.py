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
import zipfile
from unittest.mock import patch

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "build"))
import build

# The 11-member Linux layout: the 9 payload/installer files every Linux
# archive has always had, plus update.sh and known-releases.json (S2).
LINUX_MEMBER_COUNT = 11


def _synthetic_root(tmp):
    """A synthetic packaging root: real install/ scripts (for install.sh's own
    --verify-archive checks), a minimal upstream tree, and a placeholder
    known-releases.json so package() has something to embed."""
    root = Path(tmp)
    (root / "LICENSE").write_text("synthetic license")
    shutil.copytree(ROOT / "install", root / "install")
    (root / "build").mkdir(parents=True)
    (root / "build/known-releases.json").write_text("[]\n")
    source = root / "upstream"
    (source / "vendor").mkdir(parents=True)
    (source / "LICENSE").write_text("synthetic upstream license")
    (source / "vendor/modules.txt").write_text("# github.com/ibm-messaging/mq-golang/v5 v5.5.4\n")
    output = root / "output"
    output.mkdir()
    for name in ("mq_prometheus", "mq_otel", "mq_prometheus_custom", "mq-dist", "mq-config-check"):
        (output / name).write_bytes(b"synthetic binary")
    return root, source, output


class Packages(unittest.TestCase):
    def test_separate_payload_and_installer_defaults(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, source, output = _synthetic_root(tmp)
            for exporter, other in (("prometheus", "otel"), ("otel", "prometheus")):
                with patch.object(build, "ROOT", root):
                    archive = build.package(source, output, "v0.1.0-rc.9", "linux-amd64", "a" * 40, {}, exporter)
                with tarfile.open(archive) as payload:
                    names = payload.getnames()
                    self.assertIn("mq_" + exporter, names)
                    self.assertNotIn("mq_" + other, names)
                    self.assertIn("update.sh", names)
                    self.assertIn("known-releases.json", names)
                    self.assertEqual(len(names), LINUX_MEMBER_COUNT)
                    self.assertEqual(sorted(names), sorted(set(names)))
                    installer = payload.extractfile("install.sh").read().decode()
                    self.assertIn("exporter=" + exporter + " # package default", installer)
                    metadata = json.load(payload.extractfile("build-metadata.json"))
                    self.assertEqual(metadata["exporter"], exporter)
                    self.assertEqual(metadata["variant"], "native")
                    self.assertEqual(metadata["track"], "native")
                    self.assertNotIn("patches", metadata)
                for requested, success in ((exporter, True), (other, False)):
                    # Give the wrong selector a matching checksum filename too;
                    # rejection must check the payload, not just its filename.
                    prefix = "mq-exporter-dist" if requested == "prometheus" else "mq-otel-dist"
                    sums = root / "SHA256SUMS"
                    sums.write_text(hashlib.sha256(archive.read_bytes()).hexdigest() + "  " + prefix + "-v0.1.0-rc.9-linux-amd64.tar.gz\n")
                    result = subprocess.run(["bash", str(ROOT / "install/install.sh"), "--verify-archive", str(archive), str(sums), "v0.1.0-rc.9", requested], capture_output=True)
                    self.assertEqual(result.returncode == 0, success, result.stderr.decode())
                archive.unlink()

    def test_windows_archive_does_not_gain_update_files(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, source, output = _synthetic_root(tmp)
            for name in ("mq_prometheus.exe", "mq-dist.exe", "mq-config-check.exe", "mq-service.exe"):
                (output / name).write_bytes(b"synthetic binary")
            (root / "cc/COPYING.txt").parent.mkdir(parents=True)
            (root / "cc/COPYING.txt").write_text("synthetic toolchain license")
            (root / "service/vendor").mkdir(parents=True)
            (root / "service/vendor/modules.txt").write_text("")
            with patch.object(build, "ROOT", root):
                archive = build.package(source, output, "v0.1.0-rc.9", "windows-amd64", "a" * 40, {}, "prometheus")
            with zipfile.ZipFile(archive) as payload:
                names = payload.namelist()
                self.assertNotIn("update.sh", names)
                self.assertNotIn("known-releases.json", names)

    def test_custom_variant_gets_the_custom_binary_prefix_and_metadata(self):
        with tempfile.TemporaryDirectory() as tmp:
            root, source, output = _synthetic_root(tmp)
            patches = [{"name": "qdepthhi.patch", "sha256": "d" * 64}]
            with patch.object(build, "ROOT", root):
                archive = build.package(source, output, "v6.0.0-custom-1", "linux-amd64", "a" * 40, {}, "prometheus", "custom", patches)
            self.assertEqual(archive.name, "mq-exporter-dist-custom-v6.0.0-custom-1-linux-amd64.tar.gz")
            with tarfile.open(archive) as payload:
                names = payload.getnames()
                self.assertIn("mq_prometheus_custom", names)
                self.assertNotIn("mq_prometheus", names)
                self.assertEqual(len(names), LINUX_MEMBER_COUNT)
                metadata = json.load(payload.extractfile("build-metadata.json"))
                self.assertEqual(metadata["variant"], "custom")
                self.assertEqual(metadata["track"], "custom")
                self.assertEqual(metadata["upstream_tag"], build.PINS["upstream_tag"])
                self.assertEqual(metadata["upstream_commit"], build.PINS["upstream_commit"])
                self.assertEqual(metadata["patches"], patches)
                sbom = json.load(payload.extractfile("sbom.cdx.json"))
                mq_golang = next(c for c in sbom["components"] if c["name"] == "github.com/ibm-messaging/mq-golang/v5")
                self.assertEqual(mq_golang["pedigree"]["patches"], [{"type": "unofficial", "diff": {"url": "qdepthhi.patch"}}])


if __name__ == "__main__":
    unittest.main()
