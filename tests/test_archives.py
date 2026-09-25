import hashlib
import io
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
NAMES = ['mq_prometheus', 'mq-config-check', 'mq-dist', 'install.sh', 'update.sh', 'diagnose.sh', 'LICENSE', 'THIRD-PARTY-NOTICES.txt', 'build-metadata.json', 'known-releases.json', 'sbom.cdx.json']
VERSION = 'v6.0.0-1'
ASSET = 'mq-exporter-dist-' + VERSION + '-linux-amd64.tar.gz'


class ArchiveSafety(unittest.TestCase):
    def test_archive_failures_and_scratch_ownership(self):
        with tempfile.TemporaryDirectory(prefix='mq archive tests ') as tmp:
            root = Path(tmp)
            unrelated = root / 'mq-exporter-verify.preexisting'
            unrelated.mkdir()
            sentinel = unrelated / 'keep'
            sentinel.write_text('unrelated')
            for case in ['valid', 'corrupt', 'truncated', 'mismatch', 'traversal', 'link', 'duplicate', 'unexpected']:
                with self.subTest(case=case):
                    archive = root / ASSET
                    with tarfile.open(archive, 'w:gz') as t:
                        for i, name in enumerate(NAMES):
                            if i == 0:
                                name = {'traversal': '../mq_prometheus', 'duplicate': NAMES[1], 'unexpected': 'extra'}.get(case, name)
                            info = tarfile.TarInfo(name)
                            if case == 'link' and i == 0:
                                info.type = tarfile.SYMTYPE
                                info.linkname = '/etc/passwd'
                                t.addfile(info)
                            else:
                                info.size = 4
                                t.addfile(info, io.BytesIO(b'test'))
                    sha = hashlib.sha256(archive.read_bytes()).hexdigest()
                    if case == 'corrupt':
                        archive.write_bytes(b'corrupt')
                    if case == 'truncated':
                        archive.write_bytes(archive.read_bytes()[:20])
                    if case == 'mismatch':
                        sha = '0' * 64
                    checksums = root / 'SHA256SUMS'
                    checksums.write_text(sha + '  ' + ASSET + '\n')
                    result = subprocess.run(['bash', str(ROOT / 'install/install.sh'), '--verify-archive', str(archive), str(checksums), VERSION], env={**os.environ, 'TMPDIR': tmp}, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
                    self.assertEqual(result.returncode == 0, case == 'valid', result.stderr.decode())
                    self.assertEqual(sentinel.read_text(), 'unrelated')
                    self.assertEqual(len(list(root.glob('mq-exporter-verify.*'))), 1)
