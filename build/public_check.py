"""Fail closed on common private-path/credential leaks; inspect archive members too.

The optional MQ_DIST_PRIVATE_TERMS file is outside the repository, one term per line.
It is never copied or printed. Automated checks supplement maintainer review.
"""
import os
from pathlib import Path
import re
import subprocess
import tarfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]
PATTERNS = [rb"/" + rb"Users/[^/\s]+/", rb"[A-Za-z]:\\" + rb"Users\\[^\\\s]+\\",
            rb"/" + rb"home/[A-Za-z0-9._-]+/",
            rb"gh[pousr]_[A-Za-z0-9]{30,}", rb"github_pat_[A-Za-z0-9_]{40,}",
            rb"-----BEGIN " + rb"(?:RSA |EC |OPENSSH )?PRIVATE KEY-----",
            rb"-----BEGIN PGP " + rb"PRIVATE KEY BLOCK-----"]


def inspect(data, label):
    for pattern in PATTERNS:
        if re.search(pattern, data):
            raise RuntimeError("private content detected in " + label + " (value suppressed)")
    if os.getenv("MQ_DIST_PRIVATE_TERMS"):
        terms = Path(os.environ["MQ_DIST_PRIVATE_TERMS"]).read_bytes().splitlines()
        if any(term.strip().lower() in data.lower() for term in terms if term.strip()):
            raise RuntimeError("private term detected in " + label + " (value suppressed)")


def main():
    names = subprocess.check_output(["git", "ls-files", "-z", "--cached", "--others", "--exclude-standard"], cwd=ROOT).split(b"\0")
    count = 0
    for raw in names:
        if not raw:
            continue
        name = raw.decode()
        inspect(raw, "filename")
        path = ROOT / name
        if path.is_file():
            inspect(path.read_bytes(), name)
            count += 1
    # Inspect the actual index, which may differ from working files.
    staged = subprocess.check_output(["git", "diff", "--cached", "--binary"], cwd=ROOT)
    inspect(staged, "staged diff")
    inspect(subprocess.check_output(["git", "log", "--all", "--format=%B"], cwd=ROOT), "commit messages")
    for path in (ROOT / "dist").glob("*"):
        if path.name.endswith(".tar.gz"):
            with tarfile.open(path) as t:
                for member in t:
                    if not member.isfile() or "/" in member.name or "\\" in member.name:
                        raise RuntimeError("unsafe release member")
                    inspect(t.extractfile(member).read(), path.name + ":" + member.name)
        elif path.suffix == ".zip":
            with zipfile.ZipFile(path) as z:
                for member in z.namelist():
                    if "/" in member or "\\" in member:
                        raise RuntimeError("unsafe release member")
                    inspect(z.read(member), path.name + ":" + member)
        elif path.is_file():
            inspect(path.read_bytes(), path.name)
    print("Public-content check passed: " + str(count) + " source files, index, commit messages and available release payloads")


if __name__ == "__main__":
    main()
