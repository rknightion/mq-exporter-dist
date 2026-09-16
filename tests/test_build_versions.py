"""Release version grammar stops before any build on an uncommitted checkout."""
from pathlib import Path
import sys
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / 'build'))
import build


class BuildVersionTests(unittest.TestCase):
    def test_stable_and_candidate_reach_source_guard(self):
        for version in ('v6.0.0', 'v6.0.0-rc.1'):
            with self.subTest(version=version), patch.object(sys, 'argv', ['build', 'linux', version]), \
                    patch.object(build, 'run', side_effect=[build.PINS['go_version'], ' M synthetic']):
                with self.assertRaisesRegex(RuntimeError, 'commit and review'):
                    build.main()

    def test_untrusted_version_rejected_before_source_access(self):
        with patch.object(sys, 'argv', ['build', 'linux', 'v6.0.0;id']), \
                patch.object(build, 'run', return_value=build.PINS['go_version']) as run:
            with self.assertRaises(ValueError):
                build.main()
            self.assertEqual(run.call_count, 1)
