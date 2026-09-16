"""Publication requires reviewed independent publisher verification receipts."""
import json
from pathlib import Path
from urllib.parse import urlparse

root = Path(__file__).resolve().parent
pins = json.loads((root / 'inputs.json').read_text())
receipts = json.loads((root / 'publisher-verification.json').read_text())
for platform in ('linux', 'windows'):
    receipt = receipts[platform]
    if receipt['sha256'] != pins['mq_' + platform + '_sha256'] or not receipt['method'] or urlparse(receipt['source'] or '').hostname not in ('www.ibm.com', 'public.dhe.ibm.com'):
        raise SystemExit('PUBLICATION BLOCKED: independently verify the ' + platform + ' SDK with IBM signature/checksum evidence and record the reviewed receipt')
print('Independent SDK publisher verification receipts match the build pins')
