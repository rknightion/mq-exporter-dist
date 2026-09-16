package dist

import (
	"encoding/json"
	"strings"
	"testing"
)

func TestConfiguration(t *testing.T) {
	c := Config{QMgr: "QM1", Port: 9157, Queues: "APP.*,!SYSTEM.*", Channels: "*", Mode: "client", Channel: "APP.SVRCONN", ConnName: "mq.example.com(1414)", PasswordFile: `C:\Program Files\MQ\secret.txt`, User: "monitor"}
	b, err := Render(c)
	if err != nil {
		t.Fatal(err)
	}
	var v map[string]any
	if err = json.Unmarshal(b, &v); err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(string(b), "!SYSTEM.*") || v["connection"].(map[string]any)["connName"] != c.ConnName {
		t.Fatal(string(b))
	}
	for _, q := range []string{"", ", ,", "!SYSTEM.*", "APP.*,!APP.*", "*,!*", "$(touch sentinel)"} {
		bad := c
		bad.Queues = q
		if _, err := Render(bad); err == nil {
			t.Fatalf("accepted %q", q)
		}
	}
	for _, p := range []int{0, -1, 65536} {
		bad := c
		bad.Port = p
		if _, err := Render(bad); err == nil {
			t.Fatal(p)
		}
	}
	c.Mode = "bindings"
	if _, err := Render(c); err == nil {
		t.Fatal("client settings in bindings mode")
	}
}
