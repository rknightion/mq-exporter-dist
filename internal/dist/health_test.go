package dist

import (
	"net/http"
	"net/http/httptest"
	"testing"
)

func TestHealthSamples(t *testing.T) {
	if _, err := Health([]byte("ibmmq_qmgr_status{other=\"QM1\"} 2\n"), ""); err == nil {
		t.Fatal("empty manager accepted")
	}
	for _, tc := range []struct {
		body string
		ok   bool
	}{
		{"ibmmq_qmgr_status{qmgr=\"QM1\"} 2\nibmmq_queue_depth{qmgr=\"QM1\",queue=\"APP.QUEUE\"} 0\n", true},
		{"ibmmq_qmgr_status{other=\"x\",qmgr=\"QM1\"} 2e+00\r\n", true},
		{"ibmmq_qmgr_status{qmgr=\"QM1\"} 0\n", false},
		{"ibmmq_qmgr_status{notqmgr=\"QM1\"} 2\n", false},
		{"ibmmq_qmgr_status{qmgr=\"QM2\"} 2\n", false},
		{"other_qmgr_status{qmgr=\"QM1\"} 2\n", false},
		{"ibmmq_qmgr_status{qmgr=\"QM1\"} 2junk\n", false},
		{"ibmmq_qmgr_status{qmgr=\"QM1\",qmgr=\"QM1\"} 2\n", false},
		{"ibmmq_qmgr_status{qmgr=\"QM1\"} 2\nibmmq_qmgr_status{qmgr=\"QM1\"} 0\n", false},
	} {
		r, e := Health([]byte(tc.body), "QM1")
		if (e == nil && r.Connected) != tc.ok {
			t.Fatalf("%q: %+v %v", tc.body, r, e)
		}
	}
}

func TestDepthHighLimitSeriesCountsOnlyThisQueueManager(t *testing.T) {
	body := "ibmmq_qmgr_status{qmgr=\"QM1\"} 2\n" +
		"ibmmq_queue_attribute_depth_high_limit{qmgr=\"QM1\",queue=\"APP.Q1\"} 80\n" +
		"ibmmq_queue_attribute_depth_high_limit{qmgr=\"QM1\",queue=\"APP.Q2\"} 0\n" +
		"ibmmq_queue_attribute_depth_high_limit{qmgr=\"QM2\",queue=\"APP.Q1\"} 35\n" +
		"ibmmq_queue_attribute_max_depth{qmgr=\"QM1\",queue=\"APP.Q1\"} 5000\n"
	r, err := Health([]byte(body), "QM1")
	if err != nil || r.DepthHighLimitSeries != 2 || r.QueueSeries != 3 {
		t.Fatalf("got %+v, %v", r, err)
	}
}

func TestPartialHTTP(t *testing.T) {
	s := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		w.Header().Set("Content-Length", "999")
		_, _ = w.Write([]byte("ibmmq_qmgr_status{qmgr=\"QM1\"} 2\n"))
	}))
	defer s.Close()
	if _, e := FetchHealth(s.URL, "QM1"); e == nil {
		t.Fatal("partial body accepted")
	}
}
