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
    def test_secret_file_is_private_and_never_overwrites_existing_content(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / 'secret'
            rpm_sign.write_secret(path, 'synthetic')
            self.assertEqual(path.stat().st_mode & 0o777, 0o600)
            with self.assertRaises(FileExistsError):
                rpm_sign.write_secret(path, 'replacement')
            self.assertEqual(path.read_text(), 'synthetic')

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

    def test_package_name_accepts_revision_and_candidate_forms(self):
        valid = ['mq-prometheus-6.0.0-6.0.0.mqdist.x86_64.rpm',
                 'mq-otel-6.0.0-6.0.0_1.mqdist.x86_64.rpm',
                 'mq-prometheus-6.0.0-6.0.0_1~rc.2.mqdist.x86_64.rpm',
                 'mq-otel-6.0.0-6.0.0~rc.1.mqdist.x86_64.rpm']
        for name in valid:
            with self.subTest(name=name):
                self.assertTrue(rpm_sign.PACKAGE_NAME.fullmatch(name))
        invalid = ['mq-prometheus-6.0.0-6.0.0_01.mqdist.x86_64.rpm',
                   'mq-prometheus-6.0.0-6.0.0_1~rc.02.mqdist.x86_64.rpm',
                   'mq-prometheus-6.0.0-6.0.0_1.mqdist.custom.x86_64.rpm']
        for name in invalid:
            with self.subTest(name=name):
                self.assertIsNone(rpm_sign.PACKAGE_NAME.fullmatch(name))

    def test_custom_track_source_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory)
            for exporter in ('prometheus', 'otel'):
                rpm = path / f'mq-{exporter}-6.0.0-6.0.0_1.mqdist.x86_64.rpm'
                rpm.write_bytes(b'synthetic')
                digest = hashlib.sha256(b'synthetic').hexdigest()
                rpm.with_name(rpm.name + '.sha256').write_text(digest + '  ' + rpm.name + '\n')
                metadata = {'rpm_sha256': digest, 'signed': False, 'packaging_dirty': False,
                            'packaging_commit': 'a' * 40, 'source': {'distribution_commit': 'a' * 40,
                            'distribution_version': 'v6.0.0-custom-1', 'platform': 'linux-amd64', 'exporter': exporter}}
                rpm.with_name(rpm.name + '.metadata.json').write_text(json.dumps(metadata))
            with self.assertRaises(ValueError):
                rpm_sign.packages(path, 'a' * 40)

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
