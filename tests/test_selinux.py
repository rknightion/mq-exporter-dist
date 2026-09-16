"""Only installer-owned paths may be relabelled; failures must stop installation."""
from pathlib import Path
import subprocess
import unittest


class SELinuxTests(unittest.TestCase):
    def test_labels_and_failure(self):
        source = (Path(__file__).parents[1] / "install/install.sh").read_text()
        definitions = source.split('if [[ ${1:-} == --verify-archive ]]; then', 1)[0]
        for enabled, code, expected in ((False, 0, True), (True, 0, True), (True, 1, False)):
            script = definitions + '\nselinux_active() { ' + ('true' if enabled else 'false') + '; }\n'
            script += f'restorecon() {{ printf "%s\\n" "$@"; return {code}; }}\n'
            script += 'restore_labels "/opt/mq exporter/qm1" "/etc/systemd/system/mq-exporter-qm1.service"'
            result = subprocess.run(["bash", "-c", script], capture_output=True, text=True)
            self.assertEqual(result.returncode == 0, expected, result.stderr)
            if enabled:
                self.assertEqual(result.stdout.splitlines(), ['--', '/opt/mq exporter/qm1', '/etc/systemd/system/mq-exporter-qm1.service'])
            else:
                self.assertEqual(result.stdout, '')
