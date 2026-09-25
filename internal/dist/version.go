package dist

import (
	"errors"
	"fmt"
	"regexp"
	"strconv"
	"strings"
)

// Version is the distribution release grammar shared with build/versions.py
// and pinned by tests/version-vectors.json.
//
// native: vX.Y.Z (legacy), vX.Y.Z-N, vX.Y.Z-N-rc.M
// custom: vX.Y.Z-custom-N, vX.Y.Z-custom-N-rc.M
//
// RC == 0 means a final release. SemVer tools sort vX.Y.Z-N below vX.Y.Z;
// always compare with CompareVersions rather than the raw Text.
type Version struct {
	Text     string
	Upstream string
	Track    string
	Revision int
	RC       int
}

const (
	numberPattern   = `(?:0|[1-9][0-9]*)`
	positivePattern = `[1-9][0-9]*`
)

var versionPattern = regexp.MustCompile(
	`^v(` + numberPattern + `\.` + numberPattern + `\.` + numberPattern + `)` +
		`(?:-(custom-)?(` + positivePattern + `))?` +
		`(?:-rc\.(` + positivePattern + `))?$`,
)

// ParseVersion parses a distribution release version.
func ParseVersion(s string) (Version, error) {
	m := versionPattern.FindStringSubmatch(s)
	if m == nil {
		return Version{}, fmt.Errorf("invalid distribution version: %q", s)
	}
	track := "native"
	if m[2] != "" {
		track = "custom"
	}
	revision := 0
	if m[3] != "" {
		n, err := strconv.Atoi(m[3])
		if err != nil {
			return Version{}, err
		}
		revision = n
	}
	rc := 0
	if m[4] != "" {
		n, err := strconv.Atoi(m[4])
		if err != nil {
			return Version{}, err
		}
		rc = n
	}
	return Version{Text: s, Upstream: m[1], Track: track, Revision: revision, RC: rc}, nil
}

func (v Version) upstreamTriple() [3]int {
	var triple [3]int
	for i, part := range strings.SplitN(v.Upstream, ".", 3) {
		triple[i], _ = strconv.Atoi(part)
	}
	return triple
}

// less orders (upstream triple, revision, final-after-rc, rc). A final
// (RC == 0) sorts after every candidate of the same revision.
func (v Version) less(other Version) bool {
	a, b := v.upstreamTriple(), other.upstreamTriple()
	for i := range a {
		if a[i] != b[i] {
			return a[i] < b[i]
		}
	}
	if v.Revision != other.Revision {
		return v.Revision < other.Revision
	}
	aFinal, bFinal := v.RC == 0, other.RC == 0
	if aFinal != bFinal {
		return bFinal
	}
	return v.RC < other.RC
}

// CompareVersions returns -1, 0 or 1. Comparing across tracks is an error.
func CompareVersions(a, b string) (int, error) {
	va, err := ParseVersion(a)
	if err != nil {
		return 0, err
	}
	vb, err := ParseVersion(b)
	if err != nil {
		return 0, err
	}
	if va.Track != vb.Track {
		return 0, errors.New("versions belong to different tracks")
	}
	switch {
	case va.less(vb):
		return -1, nil
	case vb.less(va):
		return 1, nil
	default:
		return 0, nil
	}
}
