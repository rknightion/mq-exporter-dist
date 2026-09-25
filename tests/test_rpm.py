"""Version identity and untrusted release inputs are packaging boundaries."""
import io
import hashlib
import json
from pathlib import Path
import sys
import tarfile
import tempfile
import unittest
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).parents[1] / "build"))
import rpm

VECTORS = json.loads((Path(__file__).parents[1] / "tests/version-vectors.json").read_text())


class RPMTests(unittest.TestCase):
    def test_bundle_publication_collision_and_failed_write(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / 'candidate.rpm'
            original_link = rpm.os.link
            calls = []
            def fail_second(source, destination):
                calls.append(destination)
                if len(calls) == 2:
                    raise OSError('synthetic failure')
                original_link(source, destination)
            with patch.object(rpm.os, 'link', side_effect=fail_second):
                with self.assertRaises(OSError):
                    rpm.publish_bundle(target, b'candidate', {})
            self.assertEqual(list(Path(directory).iterdir()), [])
            rpm.publish_bundle(target, b'candidate', {})
            with self.assertRaises(ValueError):
                rpm.publish_bundle(target, b'changed', {})
            self.assertEqual(target.read_bytes(), b'candidate')
            self.assertEqual(json.loads(target.with_name(target.name + '.metadata.json').read_text())['rpm_sha256'], hashlib.sha256(b'candidate').hexdigest())

    def test_version_mapping_from_vectors(self):
        # Every tests/version-vectors.json rpm_release entry shares upstream 6.0.0.
        for case in VECTORS["rpm_release"]:
            with self.subTest(version=case["version"]):
                self.assertEqual(rpm.rpm_version('v6.0.0', case["version"]), ('6.0.0', case["release"]))

    def test_version_mapping_rejects_mismatched_tag_custom_and_untrusted_input(self):
        for tag, dist in [('main', 'v0.1.0'), ('v6.0.0', 'v0.1.0;id'), ('v6.0.0', 'v0.1.0\n'),
                           ('v6.0.0', 'v0.1.0'), ('v6.0.0', 'v6.0.0-custom-1')]:
            with self.subTest(tag=tag, dist=dist), self.assertRaises(ValueError):
                rpm.rpm_version(tag, dist)

    def _write_archive(self, directory, names, unsafe_member=None, exporter='prometheus', binary='mq_prometheus'):
        archive = Path(directory) / 'candidate.tar.gz'
        sums = Path(directory) / 'SHA256SUMS'
        payload = {name: b'synthetic' for name in names if name != binary}
        payload[binary] = b'synthetic'
        metadata = {'exporter': exporter, 'platform': 'linux-amd64',
                    'payload_sha256': {k: hashlib.sha256(v).hexdigest() for k, v in payload.items()}}
        payload['build-metadata.json'] = json.dumps(metadata).encode()
        with tarfile.open(archive, 'w:gz') as t:
            for name, data in payload.items():
                info = tarfile.TarInfo(unsafe_member if unsafe_member and name == 'LICENSE' else name)
                info.size = len(data)
                t.addfile(info, io.BytesIO(data))
        digest = hashlib.sha256(archive.read_bytes()).hexdigest()
        sums.write_text(digest + '  ' + archive.name + '\n')
        return archive, sums

    def test_archive_integrity_and_member_boundary(self):
        with tempfile.TemporaryDirectory() as directory:
            common = ('mq-dist', 'mq-config-check', 'install.sh', 'diagnose.sh', 'LICENSE', 'THIRD-PARTY-NOTICES.txt', 'sbom.cdx.json')
            archive, sums = self._write_archive(directory, common + ('mq_prometheus',), unsafe_member='../outside')
            with self.assertRaises(ValueError):
                rpm.verified_payload(archive, sums)
            archive, sums = self._write_archive(directory, common + ('mq_prometheus',))
            self.assertEqual(rpm.verified_payload(archive, sums)[1]['exporter'], 'prometheus')
            sums.write_text('0' * 64 + '  ' + archive.name + '\n')
            with self.assertRaises(ValueError):
                rpm.verified_payload(archive, sums)

    def test_legacy_nine_member_archive_still_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            common = ('mq-dist', 'mq-config-check', 'install.sh', 'diagnose.sh', 'LICENSE', 'THIRD-PARTY-NOTICES.txt', 'sbom.cdx.json')
            archive, sums = self._write_archive(directory, common + ('mq_otel',), exporter='otel', binary='mq_otel')
            payload, metadata, _ = rpm.verified_payload(archive, sums)
            self.assertEqual(len(payload), 9)
            self.assertEqual(metadata['exporter'], 'otel')

    def test_eleven_member_archive_with_update_and_known_releases_accepted(self):
        with tempfile.TemporaryDirectory() as directory:
            common = ('mq-dist', 'mq-config-check', 'install.sh', 'diagnose.sh', 'LICENSE',
                      'THIRD-PARTY-NOTICES.txt', 'sbom.cdx.json', 'update.sh', 'known-releases.json')
            archive, sums = self._write_archive(directory, common + ('mq_prometheus',))
            payload, metadata, _ = rpm.verified_payload(archive, sums)
            self.assertEqual(len(payload), 11)
            self.assertEqual(metadata['exporter'], 'prometheus')

    def test_custom_binary_archive_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            common = ('mq-dist', 'mq-config-check', 'install.sh', 'diagnose.sh', 'LICENSE', 'THIRD-PARTY-NOTICES.txt', 'sbom.cdx.json')
            archive, sums = self._write_archive(directory, common + ('mq_prometheus_custom',), binary='mq_prometheus_custom')
            with self.assertRaises(ValueError):
                rpm.verified_payload(archive, sums)
