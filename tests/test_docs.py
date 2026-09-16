"""Keep source links and warning text intact when rendering public docs."""
import sys
from pathlib import Path
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "build"))
from docs import render


class DocsTest(unittest.TestCase):
    def test_links(self):
        self.assertEqual(render('[Matrix](docs/compatibility.md)'), '[Matrix](compatibility.md)')
        self.assertIn('https://github.com/rknightion/mq-exporter-dist/blob/main/examples/',
                      render('[Example](examples/prometheus.yml)'))

    def test_warning(self):
        text = render('> [!WARNING]\n> No warranty.\n> Community software.\n\nBody\n')
        self.assertIn('!!! warning', text)
        self.assertIn('    No warranty.\n    Community software.', text)
        self.assertTrue(text.endswith('\nBody\n'))
