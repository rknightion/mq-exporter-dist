"""Signing authority is tied to an exact successful source run and package pair."""
import copy
import hashlib
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).parents[1] / 'build'))
import rpm_sign


class SigningTests(unittest.TestCase):
    def test_run_identity_rejects_wrong_origin_or_unfinished_checks(self):
        run = {'repository': {'full_name': rpm_sign.REPOSITORY}, 'path': '.github/workflows/candidate.yml',
               'head_branch': 'main', 'head_sha': 'a' * 40, 'event': 'workflow_dispatch',
               'status': 'completed', 'conclusion': 'success'}
        rpm_sign.validate_run(run, 'a' * 40)
        for key, value in [('head_sha', 'b' * 40), ('event', 'pull_request'), ('conclusion', 'cancelled'),
                           ('repository', {'full_name': 'example/untrusted'}), ('path', '.github/workflows/other.yml')]:
            altered = copy.deepcopy(run)
            altered[key] = value
            with self.assertRaises(ValueError):
                rpm_sign.validate_run(altered, 'a' * 40)

    def test_package_identity_checks_and_integrity(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            for exporter in ('prometheus', 'otel'):
                rpm = path / f'mq-{exporter}-6.0.0-0.1.0~rc.7.mqdist.x86_64.rpm'
                rpm.write_bytes(b'synthetic')
                digest = hashlib.sha256(b'synthetic').hexdigest()
                rpm.with_name(rpm.name + '.sha256').write_text(digest + '  ' + rpm.name + '\n')
                metadata = {'rpm_sha256': digest, 'signed': False, 'packaging_dirty': False,
                            'packaging_commit': 'a' * 40, 'source': {'distribution_commit': 'a' * 40,
                            'distribution_version': 'v0.1.0-rc.7', 'platform': 'linux-amd64', 'exporter': exporter}}
                rpm.with_name(rpm.name + '.metadata.json').write_text(json.dumps(metadata))
            self.assertEqual(len(rpm_sign.packages(path, 'a' * 40)), 2)
            with self.assertRaises(ValueError):
                rpm_sign.packages(path, 'b' * 40)
            rpm.write_bytes(b'tampered')
            with self.assertRaises(ValueError):
                rpm_sign.packages(path, 'a' * 40)
