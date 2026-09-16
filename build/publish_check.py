"""Publication requires reviewed SDK integrity records matching the build pins."""
import json
from pathlib import Path
from urllib.parse import urlparse

root = Path(__file__).resolve().parent
pins = json.loads((root / 'inputs.json').read_text())
receipts = json.loads((root / 'publisher-verification.json').read_text())
for platform in ('linux', 'windows'):
    receipt = receipts[platform]
    if receipt['sha256'] != pins['mq_' + platform + '_sha256'] or not receipt['method'] or urlparse(receipt['source'] or '').hostname not in ('www.ibm.com', 'public.dhe.ibm.com'):
        raise SystemExit('PUBLICATION BLOCKED: record the ' + platform + ' SDK source, verification method and matching SHA-256')
print('SDK integrity records match the build pins')
