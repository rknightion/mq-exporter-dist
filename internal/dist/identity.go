package dist

import (
	"encoding/json"
	"fmt"
	"os"
	"reflect"
)

// Preserved JSON configs may tune collection, but cannot silently change identity.
func SameIdentity(expected, actual string) error {
	load := func(name string) (map[string]any, error) {
		b, e := os.ReadFile(name)
		if e != nil {
			return nil, e
		}
		var v map[string]any
		e = json.Unmarshal(b, &v)
		return v, e
	}
	a, e := load(expected)
	if e != nil {
		return e
	}
	b, e := load(actual)
	if e != nil {
		return fmt.Errorf("managed configuration must remain JSON (valid YAML): %w", e)
	}
	sections := map[string][]string{"connection": {"queueManager", "clientConnection", "channel", "connName", "ccdtUrl"}, "prometheus": {"port"}}
	if _, otel := a["otel"]; otel {
		if a["prometheus"] != nil || b["prometheus"] != nil {
			return fmt.Errorf("exporter identity differs")
		}
		delete(sections, "prometheus")
		sections["otel"] = []string{"endpoint", "insecure"}
	} else if b["otel"] != nil {
		return fmt.Errorf("exporter identity differs")
	}
	for section, keys := range sections {
		left, ok := a[section].(map[string]any)
		if !ok {
			return fmt.Errorf("missing expected section")
		}
		right, ok := b[section].(map[string]any)
		if !ok {
			return fmt.Errorf("missing configuration section")
		}
		for _, k := range keys {
			if !reflect.DeepEqual(left[k], right[k]) {
				return fmt.Errorf("preserved config identity differs at %s.%s", section, k)
			}
		}
	}
	return nil
}
