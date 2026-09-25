"""Both installers pick the newest stable release per track using distribution ordering."""
import json
from pathlib import Path
import random
import subprocess
import unittest

ROOT = Path(__file__).resolve().parents[1]
VECTORS = json.loads((ROOT / "tests/version-vectors.json").read_text())


def pick(script, track, tags):
    return subprocess.run(["bash", str(ROOT / "install" / script), "--pick-latest", track], input="\n".join(tags) + "\n",
                          text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


class LatestReleaseTests(unittest.TestCase):
    def test_newest_stable_release_of_each_track(self):
        tags = VECTORS["ordered"]["native"] + VECTORS["ordered"]["custom"] + VECTORS["invalid"]
        random.Random(7).shuffle(tags)
        for script in ("install.sh", "update.sh"):
            for track, ordered in VECTORS["ordered"].items():
                with self.subTest(script=script, track=track):
                    expected = [t for t in ordered if "-rc." not in t][-1]
                    result = pick(script, track, tags)
                    self.assertEqual(result.stdout.strip(), expected, result.stderr)

    def test_candidates_only_is_not_a_release(self):
        for script in ("install.sh", "update.sh"):
            with self.subTest(script=script):
                self.assertNotEqual(pick(script, "custom", ["v6.0.0-custom-1-rc.1", "v6.0.0-1"]).returncode, 0)


if __name__ == "__main__":
    unittest.main()
