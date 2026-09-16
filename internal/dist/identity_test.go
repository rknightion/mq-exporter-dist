package dist

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestIdentityIsolation(t *testing.T) {
	c := Config{QMgr: "QM1", Port: 9157, Queues: "APP.*", Channels: "*", Mode: "bindings"}
	b, e := Render(c)
	if e != nil {
		t.Fatal(e)
	}
	d := t.TempDir()
	a := filepath.Join(d, "expected.json")
	actual := filepath.Join(d, "actual.json")
	_ = os.WriteFile(a, b, 0600)
	for _, tc := range []struct {
		old, new string
		pass     bool
	}{{"APP.*", "OTHER.*", true}, {"QM1", "QM2", false}, {"9157", "9158", false}} {
		_ = os.WriteFile(actual, []byte(strings.ReplaceAll(string(b), tc.old, tc.new)), 0600)
		if (SameIdentity(a, actual) == nil) != tc.pass {
			t.Fatal(tc)
		}
	}
}
