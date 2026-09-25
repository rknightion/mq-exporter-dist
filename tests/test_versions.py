"""The shared release grammar vectors pin parsing, tracks and ordering."""
import json
from pathlib import Path
import sys
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "build"))
import versions

VECTORS = json.loads((ROOT / "tests/version-vectors.json").read_text())


class VersionTests(unittest.TestCase):
    def test_valid(self):
        for case in VECTORS["valid"]:
            with self.subTest(case=case["version"]):
                v = versions.parse(case["version"])
                self.assertEqual((v.track, v.upstream, v.revision, v.rc), (case["track"], case["upstream"], case["revision"], case["rc"]))

    def test_invalid(self):
        for text in VECTORS["invalid"]:
            with self.subTest(text=text), self.assertRaises(ValueError):
                versions.parse(text)

    def test_order(self):
        for track, ordered in VECTORS["ordered"].items():
            for low, high in zip(ordered, ordered[1:]):
                with self.subTest(low=low, high=high):
                    self.assertEqual(versions.compare(low, high), -1)
                    self.assertEqual(versions.compare(high, low), 1)
            self.assertEqual(versions.compare(ordered[0], ordered[0]), 0)

    def test_cross_track_is_an_error(self):
        for a, b in VECTORS["cross_track"]:
            with self.assertRaises(ValueError):
                versions.compare(a, b)


if __name__ == "__main__":
    unittest.main()
