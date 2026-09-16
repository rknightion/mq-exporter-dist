"""Native MQ directory ownership must not relax the install-tree trust boundary."""
from pathlib import Path
import subprocess
import unittest


class RuntimeOwnerTests(unittest.TestCase):
    def test_runtime_owner_boundary(self):
        # Load definitions only, before the installer's first argument dispatch.
        source = (Path(__file__).parents[1] / "install/install.sh").read_text()
        definitions = source.split('if [[ ${1:-} == --verify-archive ]]; then', 1)[0]
        cases = [
            ("/opt/mqm", "0", "/opt/mqm", True),
            ("/opt/mqm", "991", "/opt/mqm", True),
            ("/opt", "991", "/opt/mqm", False),
            ("/opt/exporter", "991", "", False),
            ("/opt/mqm", "992", "/opt/mqm", False),
        ]
        for path, owner, runtime, expected in cases:
            with self.subTest(path=path, owner=owner, runtime=runtime):
                result = subprocess.run(
                    ["bash", "-c", definitions + '\nid() { echo 991; }\n'
                     + 'trusted_directory_owner "$1" "$2" "$3"',
                     "test", path, owner, runtime], check=False)
                self.assertEqual(result.returncode == 0, expected)
        result = subprocess.run(
            ["bash", "-c", definitions + '\nid() { return 1; }\n'
             + 'trusted_directory_owner /opt/mqm 991 /opt/mqm'], check=False)
        self.assertNotEqual(result.returncode, 0)
