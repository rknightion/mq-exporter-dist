"""Sign copies of two verified CI packages; never publish or rebuild them."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

from public_check import inspect

ROOT = Path(__file__).resolve().parents[1]
REPOSITORY = 'rknightion/mq-exporter-dist'


def sha(data):
    return hashlib.sha256(data).hexdigest()


def write_secret(path, value):
    with open(path, 'x', encoding='utf-8', opener=lambda p, f: os.open(p, f, 0o600)) as stream:
        stream.write(value)


def validate_run(run, commit):
    if (run.get('repository', {}).get('full_name') != REPOSITORY
            or run.get('path') != '.github/workflows/candidate.yml'
            or run.get('head_branch') != 'main' or run.get('head_sha') != commit
            or run.get('event') != 'workflow_dispatch' or run.get('conclusion') != 'success'
            or run.get('status') != 'completed'):
        raise ValueError('source must be a successful main Candidate run at this exact commit')


def preflight(run_id):
    if not re.fullmatch(r'[1-9][0-9]*', run_id):
        raise ValueError('invalid run ID')
    run = json.loads(subprocess.check_output(['gh', 'api', f'repos/{REPOSITORY}/actions/runs/{run_id}']))
    validate_run(run, os.environ['GITHUB_SHA'])
    listing = json.loads(subprocess.check_output(['gh', 'api', f'repos/{REPOSITORY}/actions/runs/{run_id}/artifacts?per_page=100']))
    selected = [a for a in listing['artifacts'] if a['name'].startswith('unsigned-rpm-')]
    if (len(selected) != 2 or {a['name'] for a in selected} != {'unsigned-rpm-prometheus', 'unsigned-rpm-otel'}
            or any(a['expired'] or a['size_in_bytes'] > 256 * 1024 * 1024 for a in selected)):
        raise ValueError('source must contain exactly two available unsigned RPM artifacts')
    record = {'run_id': int(run_id), 'run_attempt': run['run_attempt'], 'commit': run['head_sha'],
              'artifacts': [{k: a[k] for k in ('id', 'name', 'digest')} for a in selected]}
    Path('.work').mkdir(exist_ok=True)
    Path('.work/rpm-source.json').write_text(json.dumps(record, indent=2) + '\n')
    with open(os.environ['GITHUB_OUTPUT'], 'a') as stream:
        stream.write('artifact_ids=' + ','.join(str(a['id']) for a in selected) + '\n')
    print('Verified source run identity and two immutable artifact IDs')


def packages(directory, commit):
    files = list(directory.iterdir())
    rpms = sorted(directory.glob('*.rpm'))
    if len(rpms) != 2 or len(files) != 6 or any(p.is_symlink() or not p.is_file() for p in files):
        raise ValueError('expected two regular RPMs and their checksum/metadata sidecars only')
    records = []
    for rpm in rpms:
        if not re.fullmatch(r'mq-(prometheus|otel)-[0-9]+\.[0-9]+\.[0-9]+-[0-9]+\.[0-9]+\.[0-9]+(?:~rc\.[0-9]+)?\.mqdist\.x86_64\.rpm', rpm.name):
            raise ValueError('unexpected package name')
        data = rpm.read_bytes()
        if rpm.with_name(rpm.name + '.sha256').read_text() != sha(data) + '  ' + rpm.name + '\n':
            raise ValueError('package checksum mismatch')
        meta = json.loads(rpm.with_name(rpm.name + '.metadata.json').read_text())
        if (meta['rpm_sha256'] != sha(data) or meta['signed'] is not False
                or meta['packaging_dirty'] is not False or meta['packaging_commit'] != commit
                or meta['source']['distribution_commit'] != commit
                or meta['source']['platform'] != 'linux-amd64'
                or not rpm.name.startswith('mq-' + meta['source']['exporter'] + '-')):
            raise ValueError('package source identity mismatch')
        records.append((rpm, meta))
    if ({m['source']['exporter'] for _, m in records} != {'prometheus', 'otel'}
            or len({m['source']['distribution_version'] for _, m in records}) != 1):
        raise ValueError('need both exporters from the same distribution version')
    return records


def sign(directory, output, source):
    commit = subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip()
    if source['commit'] != commit:
        raise ValueError('signer and candidate commits differ')
    records = packages(directory, commit)
    keys = json.loads((ROOT / 'keys/signing-key.json').read_text())['keys']
    primary = next(k['fingerprint'] for k in keys if k['role'] == 'certification')
    signing = next(k['fingerprint'] for k in keys if k['role'] == 'signing')
    if os.environ['RPM_PRIMARY_FINGERPRINT'] != primary or os.environ['RPM_SIGNING_FINGERPRINT'] != signing:
        raise ValueError('secret key identity differs from the published trust anchor')
    image = subprocess.check_output(['docker', 'image', 'inspect', 'mq-dist-rpm-sign', '--format', '{{.Id}}'], text=True).strip()
    output.mkdir(parents=True, exist_ok=False)
    # Secrets never enter the build context, command arguments or artifact directory.
    with tempfile.TemporaryDirectory(prefix='mq-rpm-sign-') as tmp:
        secret = Path(tmp)
        (secret / 'gnupg').mkdir(mode=0o700)
        for name, variable in [('key.asc', 'RPM_SIGNING_KEY'), ('passphrase', 'RPM_SIGNING_PASSPHRASE')]:
            write_secret(secret / name, os.environ.pop(variable))
        command = ['docker', 'run', '--rm', '--platform', 'linux/amd64', '--network=none',
                   '--user', f'{os.getuid()}:{os.getgid()}',
                   '-v', str(secret) + ':/secrets', '-v', str(output.resolve()) + ':/packages', image]

        def run(args):
            result = subprocess.run(command + args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
            if result.returncode:
                # Do not echo key-processing diagnostics or captured secret-bearing output.
                raise RuntimeError('isolated signing command failed: ' + args[0])
            return result.stdout

        gpg = ['gpg2', '--homedir', '/secrets/gnupg', '--batch', '--pinentry-mode', 'loopback',
               '--passphrase-file', '/secrets/passphrase']
        run(gpg + ['--import', '/secrets/key.asc'])
        listing = run(gpg + ['--with-colons', '--list-secret-keys']).decode().splitlines()
        sec = [line.split(':') for line in listing if line.startswith('sec:')]
        sub = [line.split(':') for line in listing if line.startswith('ssb:')]
        fingerprints = [line.split(':')[9] for line in listing if line.startswith('fpr:')]
        if len(sec) != 1 or sec[0][14] != '#' or len(sub) != 1 or fingerprints != [primary, signing]:
            raise ValueError('CI requires only the exact signing subkey, with no certification secret')
        manifest = {'candidate_only': '-rc.' in records[0][1]['source']['distribution_version'],
                    'source': source, 'signing_fingerprint': signing,
                    'primary_fingerprint': primary, 'signing_image': image,
                    'tool_inventory': run(['rpm', '-qa', '--qf', '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n']).decode().splitlines(),
                    'packages': []}
        for rpm, metadata in records:
            target = output / rpm.name
            shutil.copyfile(rpm, target)
            before = sha(run(['rpm2cpio', '/packages/' + rpm.name]))
            run(['rpmsign', '--addsign', '--define', '_gpg_name ' + signing + '!',
                 '--define', '_gpg_path /secrets/gnupg', '--define', '_gpg_digest_algo sha256',
                 '--define', '_gpg_sign_cmd_extra_args --batch --pinentry-mode loopback --passphrase-file /secrets/passphrase',
                 '/packages/' + rpm.name])
            if sha(run(['rpm2cpio', '/packages/' + rpm.name])) != before:
                raise ValueError('signing changed the RPM payload')
            manifest['packages'].append({'name': rpm.name, 'unsigned_sha256': metadata['rpm_sha256'],
                                         'signed_sha256': sha(target.read_bytes()), 'cpio_sha256': before,
                                         'unsigned_build': metadata})
        shutil.copyfile(ROOT / 'keys/RPM-GPG-KEY-mq-exporter-dist', output / 'RPM-GPG-KEY-mq-exporter-dist')
        run(['createrepo_c', '--checksum', 'sha256', '/packages'])
        (output / 'signed-metadata.json').write_text(json.dumps(manifest, indent=2, sort_keys=True) + '\n')
        sums = ''.join(sha(p.read_bytes()) + '  ' + p.relative_to(output).as_posix() + '\n'
                       for p in sorted(output.rglob('*')) if p.is_file())
        (output / 'SHA256SUMS').write_text(sums)
        for name in ('repodata/repomd.xml', 'SHA256SUMS'):
            run(gpg + ['--local-user', signing + '!', '--digest-algo', 'SHA256', '--armor', '--detach-sign', '/packages/' + name])
        run(['gpgconf', '--homedir', '/secrets/gnupg', '--kill', 'all'])
    for path in output.rglob('*'):
        if path.is_file():
            inspect(path.read_bytes(), path.relative_to(output).as_posix())
    print('Signed two candidate RPM copies and repository metadata; payloads unchanged')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest='operation', required=True)
    pre = sub.add_parser('preflight')
    pre.add_argument('run_id')
    signer = sub.add_parser('sign')
    signer.add_argument('packages', type=Path)
    signer.add_argument('output', type=Path)
    args = parser.parse_args()
    if args.operation == 'preflight':
        preflight(args.run_id)
    else:
        sign(args.packages, args.output, json.loads(Path('.work/rpm-source.json').read_text()))


if __name__ == '__main__':
    main()
