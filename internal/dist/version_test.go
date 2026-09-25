package dist

import (
	"encoding/json"
	"os"
	"path/filepath"
	"runtime"
	"testing"
)

// vectorsPath resolves tests/version-vectors.json relative to this file, not
// the working directory, so `go test ./...` from any location finds it.
func vectorsPath(t *testing.T) string {
	_, thisFile, _, ok := runtime.Caller(0)
	if !ok {
		t.Fatal("could not resolve caller")
	}
	return filepath.Join(filepath.Dir(thisFile), "..", "..", "tests", "version-vectors.json")
}

type vectors struct {
	Valid []struct {
		Version  string `json:"version"`
		Track    string `json:"track"`
		Upstream string `json:"upstream"`
		Revision int    `json:"revision"`
		RC       *int   `json:"rc"`
	} `json:"valid"`
	Invalid []string            `json:"invalid"`
	Ordered map[string][]string `json:"ordered"`
	Cross   [][2]string         `json:"cross_track"`
}

func loadVectors(t *testing.T) vectors {
	b, err := os.ReadFile(vectorsPath(t))
	if err != nil {
		t.Fatal(err)
	}
	var v vectors
	if err := json.Unmarshal(b, &v); err != nil {
		t.Fatal(err)
	}
	return v
}

func TestParseVersionValid(t *testing.T) {
	v := loadVectors(t)
	for _, c := range v.Valid {
		c := c
		t.Run(c.Version, func(t *testing.T) {
			parsed, err := ParseVersion(c.Version)
			if err != nil {
				t.Fatal(err)
			}
			wantRC := 0
			if c.RC != nil {
				wantRC = *c.RC
			}
			if parsed.Track != c.Track || parsed.Upstream != c.Upstream || parsed.Revision != c.Revision || parsed.RC != wantRC {
				t.Fatalf("ParseVersion(%q) = %+v, want track=%s upstream=%s revision=%d rc=%d",
					c.Version, parsed, c.Track, c.Upstream, c.Revision, wantRC)
			}
		})
	}
}

func TestParseVersionInvalid(t *testing.T) {
	v := loadVectors(t)
	for _, text := range v.Invalid {
		text := text
		t.Run(text, func(t *testing.T) {
			if _, err := ParseVersion(text); err == nil {
				t.Fatalf("ParseVersion(%q) succeeded, want error", text)
			}
		})
	}
}

func TestCompareVersionsOrdered(t *testing.T) {
	v := loadVectors(t)
	for track, ordered := range v.Ordered {
		track, ordered := track, ordered
		t.Run(track, func(t *testing.T) {
			for i := 0; i < len(ordered)-1; i++ {
				low, high := ordered[i], ordered[i+1]
				if got, err := CompareVersions(low, high); err != nil || got != -1 {
					t.Fatalf("CompareVersions(%q, %q) = %d, %v, want -1, nil", low, high, got, err)
				}
				if got, err := CompareVersions(high, low); err != nil || got != 1 {
					t.Fatalf("CompareVersions(%q, %q) = %d, %v, want 1, nil", high, low, got, err)
				}
			}
			if got, err := CompareVersions(ordered[0], ordered[0]); err != nil || got != 0 {
				t.Fatalf("CompareVersions(%q, %q) = %d, %v, want 0, nil", ordered[0], ordered[0], got, err)
			}
		})
	}
}

func TestCompareVersionsCrossTrackIsAnError(t *testing.T) {
	v := loadVectors(t)
	for _, pair := range v.Cross {
		a, b := pair[0], pair[1]
		t.Run(a+"_vs_"+b, func(t *testing.T) {
			if _, err := CompareVersions(a, b); err == nil {
				t.Fatalf("CompareVersions(%q, %q) succeeded, want error", a, b)
			}
		})
	}
}
