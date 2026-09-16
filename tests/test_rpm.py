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

    def test_version_mapping(self):
        self.assertEqual(rpm.rpm_version('v6.0.0', 'v0.1.0-rc.6'), ('6.0.0', '0.1.0~rc.6.mqdist'))
        self.assertEqual(rpm.rpm_version('v6.0.0', 'v0.1.0'), ('6.0.0', '0.1.0.mqdist'))
        for tag, dist in [('main', 'v0.1.0'), ('v6.0.0', 'v0.1.0;id'), ('v6.0.0', 'v0.1.0\n')]:
            with self.assertRaises(ValueError):
                rpm.rpm_version(tag, dist)

    def test_archive_integrity_and_member_boundary(self):
        with tempfile.TemporaryDirectory() as directory:
            archive = Path(directory) / 'candidate.tar.gz'
            sums = Path(directory) / 'SHA256SUMS'
            for unsafe in (False, True):
                payload = {name: b'synthetic' for name in ('mq_prometheus', 'mq-dist', 'mq-config-check', 'install.sh', 'diagnose.sh', 'LICENSE', 'THIRD-PARTY-NOTICES.txt', 'sbom.cdx.json')}
                metadata = {'exporter': 'prometheus', 'platform': 'linux-amd64', 'payload_sha256': {k: hashlib.sha256(v).hexdigest() for k,v in payload.items()}}
                payload['build-metadata.json'] = json.dumps(metadata).encode()
                with tarfile.open(archive, 'w:gz') as t:
                    for name, data in payload.items():
                        info = tarfile.TarInfo('../outside' if unsafe and name == 'LICENSE' else name)
                        info.size = len(data)
                        t.addfile(info, io.BytesIO(data))
                digest = hashlib.sha256(archive.read_bytes()).hexdigest()
                sums.write_text(digest + '  ' + archive.name + '\n')
                if unsafe:
                    with self.assertRaises(ValueError):
                        rpm.verified_payload(archive, sums)
                else:
                    self.assertEqual(rpm.verified_payload(archive, sums)[1]['exporter'], 'prometheus')
                    sums.write_text('0' * 64 + '  ' + archive.name + '\n')
                    with self.assertRaises(ValueError):
                        rpm.verified_payload(archive, sums)
