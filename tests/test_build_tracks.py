"""Version/track guards in build.py are a release-safety contract: no Docker
involved, so these run everywhere `python3 -m unittest discover` does."""
import sys
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "build"))
import build


class ResolveTrack(unittest.TestCase):
    def test_native_version_is_accepted_for_either_exporter(self):
        for platform, exporter in (("linux", "prometheus"), ("linux", "otel"), ("windows", "prometheus"), ("windows", "otel")):
            version = build.resolve_track("v6.0.0-1", platform, exporter)
            self.assertEqual(version.track, "native")

    def test_custom_version_is_accepted_only_for_linux_prometheus(self):
        version = build.resolve_track("v6.0.0-custom-1", "linux", "prometheus")
        self.assertEqual(version.track, "custom")

    def test_custom_version_rejected_on_windows(self):
        with self.assertRaises(ValueError):
            build.resolve_track("v6.0.0-custom-1", "windows", "prometheus")

    def test_custom_version_rejected_for_otel(self):
        with self.assertRaises(ValueError):
            build.resolve_track("v6.0.0-custom-1", "linux", "otel")

    def test_upstream_part_must_match_the_pinned_tag(self):
        pinned = build.PINS["upstream_tag"]
        self.assertEqual(pinned, "v6.0.0")
        with self.assertRaises(ValueError):
            build.resolve_track("v7.0.0-1", "linux", "prometheus")

    def test_invalid_version_grammar_is_rejected(self):
        with self.assertRaises(ValueError):
            build.resolve_track("6.0.0", "linux", "prometheus")


if __name__ == "__main__":
    unittest.main()
