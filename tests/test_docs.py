"""Keep source links and warning text intact when rendering public docs."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "build"))
from docs import PAGES, render


class DocsTest(unittest.TestCase):
    def test_public_navigation_excludes_internal_records(self):
        self.assertTrue({'linux.md', 'windows.md', 'prometheus.md', 'otel.md'} <= set(PAGES.values()))
        self.assertTrue({'evidence.md', 'release-v0.1.0.md', 'maintaining.md'}.isdisjoint(PAGES.values()))

    def test_links(self):
        self.assertEqual(render('[Matrix](docs/compatibility.md)'), '[Matrix](compatibility.md)')
        self.assertIn('https://github.com/rknightion/mq-exporter-dist/blob/main/examples/',
                      render('[Example](examples/prometheus.yml)'))

    def test_warning(self):
        text = render('> [!WARNING]\n> No warranty.\n> Community software.\n\nBody\n')
        self.assertIn('!!! warning', text)
        self.assertIn('    No warranty.\n    Community software.', text)
        self.assertTrue(text.endswith('\nBody\n'))
