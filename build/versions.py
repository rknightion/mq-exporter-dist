"""Distribution release grammar shared by build and release tooling.

native: vX.Y.Z (legacy), vX.Y.Z-N, vX.Y.Z-N-rc.M, legacy vX.Y.Z-rc.M
custom: vX.Y.Z-custom-N, vX.Y.Z-custom-N-rc.M
SemVer tools sort vX.Y.Z-N below vX.Y.Z; always compare with sort_key().
"""
from dataclasses import dataclass
import re

NUMBER = r"(?:0|[1-9][0-9]*)"
POSITIVE = r"[1-9][0-9]*"
PATTERN = re.compile(r"v(" + NUMBER + r"\." + NUMBER + r"\." + NUMBER + r")(?:-(custom-)?(" + POSITIVE + r"))?(?:-rc\.(" + POSITIVE + r"))?")


@dataclass(frozen=True)
class Version:
    text: str
    upstream: str
    track: str
    revision: int
    rc: int | None

    @property
    def upstream_tag(self):
        return "v" + self.upstream

    @property
    def prerelease(self):
        return self.rc is not None

    def sort_key(self):
        # A final sorts after every candidate of the same revision.
        return (tuple(int(p) for p in self.upstream.split(".")), self.revision, self.rc is None, self.rc or 0)


def parse(text):
    m = PATTERN.fullmatch(text)
    if not m:
        raise ValueError("invalid distribution version")
    track = "custom" if m[2] else "native"
    return Version(text, m[1], track, int(m[3] or 0), int(m[4]) if m[4] else None)


def compare(a, b):
    a, b = parse(a), parse(b)
    if a.track != b.track:
        raise ValueError("versions belong to different tracks")
    return (a.sort_key() > b.sort_key()) - (a.sort_key() < b.sort_key())
