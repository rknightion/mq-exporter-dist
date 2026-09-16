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

func TestExporterIdentity(t *testing.T) {
	c := Config{Exporter: "otel", Endpoint: "https://otel.example.com:4318", QMgr: "QM1", Queues: "APP.*", Channels: "*", Mode: "bindings"}
	b, err := Render(c)
	if err != nil {
		t.Fatal(err)
	}
	d := t.TempDir()
	a, actual := filepath.Join(d, "expected"), filepath.Join(d, "actual")
	if err := os.WriteFile(a, b, 0600); err != nil {
		t.Fatal(err)
	}
	for _, tc := range []struct {
		old, new string
		pass     bool
	}{
		{"APP.*", "OTHER.*", true}, {"otel.example.com", "other.example.com", false}, {`"insecure": "false"`, `"insecure": "true"`, false}, {`"otel":`, `"prometheus":`, false},
	} {
		if err := os.WriteFile(actual, []byte(strings.ReplaceAll(string(b), tc.old, tc.new)), 0600); err != nil {
			t.Fatal(err)
		}
		if (SameIdentity(a, actual) == nil) != tc.pass {
			t.Fatal(tc)
		}
	}
}
