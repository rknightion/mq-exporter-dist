"""Disposable EL8/EL9 RPM transactions; not native lifecycle acceptance."""
import argparse
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('packages', type=Path)
    args = parser.parse_args()
    packages = args.packages.resolve()
    if len(list(packages.glob('*.rpm'))) != 2:
        raise ValueError('provide exactly the two candidate RPMs in an isolated directory')
    pins = json.loads((ROOT / 'build/inputs.json').read_text())
    for platform, key in [('el8', 'linux_image'), ('el9', 'linux_validation_image')]:
        tag = 'mq-dist-rpm-test-' + platform
        subprocess.run(['docker', 'build', '--platform', 'linux/amd64', '--build-arg', 'BASE=' + pins[key],
                        '-f', str(ROOT / 'build/rpm-test.Dockerfile'), '-t', tag, str(ROOT / 'build')], check=True)
        image = subprocess.check_output(['docker', 'image', 'inspect', tag, '--format', '{{.Id}}'], text=True).strip()
        subprocess.run(['docker', 'run', '--rm', '--platform', 'linux/amd64', '--network=none',
                        '-e', 'MQ_DIST_RPM_TEST=1', '-v', str(packages) + ':/packages:ro',
                        '-v', str(ROOT / 'tests') + ':/project/tests:ro', image, 'bash', '/project/tests/rpm-install.sh'], check=True)
        print(platform + ': transaction tests passed; native SELinux/systemd not tested', flush=True)


if __name__ == '__main__':
    main()
