package dist

import (
	"bufio"
	"bytes"
	"fmt"
	"io"
	"math"
	"net/http"
	"regexp"
	"strconv"
	"strings"
	"time"
)

type HealthResult struct {
	Connected   bool    `json:"connected"`
	Status      float64 `json:"status"`
	QueueSeries int     `json:"queue_series"`
	// Samples of the custom variant's QDEPTHHI gauge; always 0 for native builds.
	DepthHighLimitSeries int    `json:"depth_high_limit_series"`
	Coverage             string `json:"coverage"`
}

var sample = regexp.MustCompile(`^([a-zA-Z_:][a-zA-Z0-9_:]*)\{(.*)\}\s+([^\s]+)(?:\s+[0-9]+)?$`)
var label = regexp.MustCompile(`^\s*([a-zA-Z_][a-zA-Z0-9_]*)="((?:[^"\\]|\\[\\"n])*)"\s*(,|$)`)

func Health(b []byte, qmgr string) (HealthResult, error) {
	result := HealthResult{Coverage: "no queue series observed"}
	if !objectName.MatchString(qmgr) {
		return result, fmt.Errorf("explicit queue manager name required")
	}
	count := 0
	s := bufio.NewScanner(bytes.NewReader(b))
	s.Buffer(make([]byte, 4096), 1024*1024)
	for s.Scan() {
		line := strings.TrimSpace(s.Text())
		if line == "" || strings.HasPrefix(line, "#") {
			continue
		}
		m := sample.FindStringSubmatch(line)
		if m == nil {
			if strings.HasPrefix(line, "ibmmq_") {
				return result, fmt.Errorf("malformed MQ sample")
			}
			continue
		}
		if m[1] != "ibmmq_qmgr_status" && !strings.HasPrefix(m[1], "ibmmq_queue_") {
			continue
		}
		labels := map[string]string{}
		rest := m[2]
		for rest != "" {
			l := label.FindStringSubmatch(rest)
			if l == nil {
				return result, fmt.Errorf("malformed labels")
			}
			if _, ok := labels[l[1]]; ok {
				return result, fmt.Errorf("duplicate label")
			}
			v, e := strconv.Unquote(`"` + l[2] + `"`)
			if e != nil {
				return result, e
			}
			labels[l[1]] = v
			rest = rest[len(l[0]):]
			if l[3] == "," && rest == "" {
				return result, fmt.Errorf("trailing comma")
			}
		}
		value, e := strconv.ParseFloat(m[3], 64)
		if e != nil || math.IsNaN(value) || math.IsInf(value, 0) {
			return result, fmt.Errorf("invalid sample value")
		}
		if labels["qmgr"] != qmgr {
			continue
		}
		if m[1] == "ibmmq_qmgr_status" {
			count++
			result.Status = value
			result.Connected = value == 2
		} else {
			result.QueueSeries++
			if m[1] == "ibmmq_queue_attribute_depth_high_limit" {
				result.DepthHighLimitSeries++
			}
		}
	}
	if e := s.Err(); e != nil {
		return result, e
	}
	if count != 1 {
		return result, fmt.Errorf("expected exactly one matching queue manager status")
	}
	if result.QueueSeries > 0 {
		result.Coverage = "queue series observed; compare names against intended queues"
	}
	return result, nil
}

func FetchHealth(url, qmgr string) (HealthResult, error) {
	client := http.Client{Timeout: 10 * time.Second}
	r, e := client.Get(url)
	if e != nil {
		return HealthResult{}, e
	}
	defer r.Body.Close()
	if r.StatusCode != 200 {
		return HealthResult{}, fmt.Errorf("HTTP status %d", r.StatusCode)
	}
	b, e := io.ReadAll(io.LimitReader(r.Body, 32*1024*1024+1))
	if e != nil {
		return HealthResult{}, e
	}
	if len(b) > 32*1024*1024 {
		return HealthResult{}, fmt.Errorf("metrics response too large")
	}
	return Health(b, qmgr)
}
