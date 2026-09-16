package dist

import (
	"encoding/json"
	"fmt"
	"path"
	"regexp"
	"strings"
)

type Config struct {
	QMgr, Queues, Channels, Mode, Channel, ConnName, CCDT, User, PasswordFile string
	Port                                                                      int
}

var objectName = regexp.MustCompile(`^[A-Za-z0-9._/%]{1,48}$`)
var patternName = regexp.MustCompile(`^!?[A-Za-z0-9._/%*]+$`)

func Patterns(s string) ([]string, error) {
	out := []string{}
	positive := []string{}
	negative := []string{}
	for _, p := range strings.Split(s, ",") {
		p = strings.TrimSpace(p)
		if p == "" {
			continue
		}
		if !patternName.MatchString(p) {
			return nil, fmt.Errorf("invalid object pattern")
		}
		out = append(out, p)
		if strings.HasPrefix(p, "!") {
			negative = append(negative, p[1:])
		} else {
			positive = append(positive, p)
		}
	}
	effective := false
	for _, p := range positive {
		excluded := false
		for _, n := range negative {
			m, _ := path.Match(n, p)
			if m || n == p {
				excluded = true
			}
		}
		if !excluded {
			effective = true
		}
	}
	if !effective {
		return nil, fmt.Errorf("patterns have no effective positive inclusion")
	}
	return out, nil
}

// JSON is also valid YAML and avoids differences in shell and PowerShell escaping.
func Render(c Config) ([]byte, error) {
	if !objectName.MatchString(c.QMgr) {
		return nil, fmt.Errorf("invalid queue manager name")
	}
	if c.Port < 1 || c.Port > 65535 {
		return nil, fmt.Errorf("port must be 1..65535")
	}
	qs, e := Patterns(c.Queues)
	if e != nil {
		return nil, e
	}
	cs, e := Patterns(c.Channels)
	if e != nil {
		return nil, e
	}
	if c.Mode != "bindings" && c.Mode != "client" {
		return nil, fmt.Errorf("mode must be bindings or client")
	}
	if c.Mode == "bindings" && (c.Channel != "" || c.ConnName != "" || c.CCDT != "") {
		return nil, fmt.Errorf("client settings require client mode")
	}
	if c.Mode == "client" {
		if c.CCDT != "" {
			if c.Channel != "" || c.ConnName != "" {
				return nil, fmt.Errorf("choose CCDT or channel and connection name")
			}
		} else if !objectName.MatchString(c.Channel) || c.ConnName == "" {
			return nil, fmt.Errorf("client requires CCDT or channel and connection name")
		}
	}
	if (c.User == "") != (c.PasswordFile == "") {
		return nil, fmt.Errorf("user and password file must be supplied together")
	}
	for _, v := range []string{c.ConnName, c.CCDT, c.User, c.PasswordFile} {
		if strings.ContainsAny(v, "\x00\r\n") {
			return nil, fmt.Errorf("control character in configuration")
		}
	}
	conn := map[string]any{"queueManager": c.QMgr, "clientConnection": c.Mode == "client", "replyQueue": "SYSTEM.DEFAULT.MODEL.QUEUE"}
	for k, v := range map[string]string{"channel": c.Channel, "connName": c.ConnName, "ccdtUrl": c.CCDT, "user": c.User, "passwordFile": c.PasswordFile} {
		if v != "" {
			conn[k] = v
		}
	}
	return json.MarshalIndent(map[string]any{
		"global":     map[string]any{"useObjectStatus": true, "useResetQStats": false, "usePublications": true, "useStatistics": false, "logLevel": "INFO", "pollInterval": "30s", "rediscoverInterval": "1h"},
		"connection": conn, "objects": map[string]any{"queues": qs, "channels": cs},
		"filters":    map[string]any{"queueSubscriptionSelector": []string{"PUT", "GET", "GENERAL"}},
		"prometheus": map[string]any{"port": fmt.Sprint(c.Port), "host": "127.0.0.1", "metricsPath": "/metrics", "namespace": "ibmmq", "keepRunning": true, "reconnectInterval": "5s"},
	}, "", "  ")
}
