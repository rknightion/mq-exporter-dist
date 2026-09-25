package dist

import (
	"crypto/sha256"
	"encoding/hex"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

type fakeHost struct {
	t    *testing.T
	root string
}

func newHost(t *testing.T) fakeHost {
	// Canonical-path checks need the resolved temporary directory.
	root, e := filepath.EvalSymlinks(t.TempDir())
	if e != nil {
		t.Fatal(e)
	}
	return fakeHost{t, root}
}

func (h fakeHost) write(p, content string, mode os.FileMode) {
	h.t.Helper()
	full := filepath.Join(h.root, p)
	if e := os.MkdirAll(filepath.Dir(full), 0o755); e != nil {
		h.t.Fatal(e)
	}
	if e := os.WriteFile(full, []byte(content), mode); e != nil {
		h.t.Fatal(e)
	}
	if e := os.Chmod(full, mode); e != nil {
		h.t.Fatal(e)
	}
}

func (h fakeHost) link(p, target string) {
	h.t.Helper()
	full := filepath.Join(h.root, p)
	os.MkdirAll(filepath.Dir(full), 0o755)
	if e := os.Symlink(target, full); e != nil {
		h.t.Fatal(e)
	}
}

func unitFor(dest, binary string) string {
	return "[Service]\nExecStart=\"" + dest + "/" + binary + "\" -f \"" + dest + "/config.json\"\n"
}

func (h fakeHost) instance(root, name, binary, variant, release string) string {
	dest := root + "/" + name
	h.write(dest+"/"+binary, "binary-"+name, 0o755)
	h.write(dest+"/identity", "QM"+name+"\n9157\nmqmon\n/opt/mqm\nbindings\n\n\n\n", 0o600)
	if variant != "" {
		h.write(dest+"/variant", variant+"\n", 0o600)
	}
	if release != "" {
		h.write(dest+"/release", release, 0o600)
	}
	h.write("/etc/systemd/system/mq-exporter-"+name+".service", unitFor(dest, binary), 0o644)
	return dest
}

func sumOf(s string) string {
	h := sha256.Sum256([]byte(s))
	return hex.EncodeToString(h[:])
}

func scan(t *testing.T, h fakeHost, roots []string, known []KnownRelease) Inventory {
	t.Helper()
	inv, e := Scanner{Sysroot: h.root, Roots: roots, Known: known, OwnerUID: uint32(os.Getuid())}.Scan()
	if e != nil {
		t.Fatal(e)
	}
	return inv
}

func TestInventoryManagedInstancesAcrossRoots(t *testing.T) {
	h := newHost(t)
	h.instance("/opt/mq-exporter", "qm1", "mq_prometheus", "", "")
	h.instance("/opt/mq exporter", "qm2", "mq_prometheus_custom", "custom", "v6.0.0-custom-1\nprometheus\ncustom\nmq_prometheus_custom\n"+sumOf("binary-qm2")+"\n")
	h.instance("/srv/mqx", "qm3", "mq_otel", "native", "v6.0.0-1\notel\nnative\nmq_otel\n"+strings.Repeat("0", 64)+"\n")
	known := []KnownRelease{{Tag: "v6.0.0", Exporter: "prometheus", Variant: "native", Platform: "linux-amd64", Payload: map[string]string{"mq_prometheus": sumOf("binary-qm1")}}}
	inv := scan(t, h, nil, known)
	if len(inv.Instances) != 3 || len(inv.Unmanaged) != 0 {
		t.Fatalf("unexpected inventory: %+v", inv)
	}
	got := map[string]Instance{}
	for _, i := range inv.Instances {
		got[i.Name] = i
	}
	if i := got["qm1"]; i.Root != "/opt/mq-exporter" || i.Variant != "native" || i.Version != "v6.0.0" || i.QMgr != "QMqm1" || i.Port != "9157" {
		t.Fatalf("legacy instance identified by published hash: %+v", i)
	}
	if i := got["qm2"]; i.Root != "/opt/mq exporter" || i.Variant != "custom" || i.Version != "v6.0.0-custom-1" {
		t.Fatalf("custom instance from release record: %+v", i)
	}
	// A release record whose hash does not match the installed binary is not trusted.
	if i := got["qm3"]; i.Exporter != "otel" || i.Version != "unrecorded" {
		t.Fatalf("stale release record accepted: %+v", i)
	}
}

func TestInventoryRejectsUnsafeOrForeignLayouts(t *testing.T) {
	h := newHost(t)
	h.instance("/opt/mq-exporter", "linked", "mq_prometheus", "", "")
	unit := "/etc/systemd/system/mq-exporter-linked.service"
	os.Remove(filepath.Join(h.root, unit))
	h.write("/elsewhere/unit", unitFor("/opt/mq-exporter/linked", "mq_prometheus"), 0o644)
	h.link(unit, filepath.Join(h.root, "/elsewhere/unit"))

	h.instance("/opt/mq-exporter", "moved", "mq_prometheus", "", "")
	h.write("/etc/systemd/system/mq-exporter-moved.service", unitFor("/opt/mq-exporter/other", "mq_prometheus"), 0o644)

	h.instance("/opt/mq-exporter", "dropin", "mq_prometheus", "", "")
	h.write("/etc/systemd/system/mq-exporter-dropin.service.d/override.conf", "[Service]\nExecStart=\nExecStart=/usr/local/bin/other\n", 0o644)

	h.instance("/opt/mq-exporter", "writable", "mq_prometheus", "", "")
	os.Chmod(filepath.Join(h.root, "/opt/mq-exporter/writable"), 0o777)

	h.instance("/opt/mq-exporter", "mismatch", "mq_prometheus", "custom", "")

	h.write("/opt/mq-exporter/orphan/identity", "QM9\n9170\nmqmon\n/opt/mqm\nbindings\n\n\n\n", 0o600)
	h.write("/usr/lib/systemd/system/mq-prometheus@.service", "[Service]\nExecStart=/usr/libexec/mq-prometheus/mq_prometheus -f /etc/mq-prometheus/%i.json\n", 0o644)
	h.write("/usr/libexec/mq-prometheus/mq_prometheus", "rpm-binary", 0o755)
	h.write("/etc/systemd/system/legacy-mq.service", "[Service]\nExecStart=/usr/local/lib/mqx/mq_prometheus -f /etc/mqx.yaml\n", 0o644)

	inv := scan(t, h, []string{"/opt/mq-exporter"}, nil)
	if len(inv.Instances) != 0 {
		t.Fatalf("unsafe layouts treated as managed: %+v", inv.Instances)
	}
	reasons := []string{}
	for _, u := range inv.Unmanaged {
		reasons = append(reasons, u.Path+": "+u.Reason)
	}
	all := strings.Join(reasons, "\n")
	for _, want := range []string{
		"mq-exporter-linked.service: unit file rejected: symlink",
		"mq-exporter-moved.service: ExecStart is not the installer layout",
		"mq-exporter-dropin.service: drop-in overrides ExecStart",
		"mq-exporter-writable.service: /opt/mq-exporter/writable rejected: group/world writable",
		"mq-exporter-mismatch.service: variant record does not match the unit binary",
		"/opt/mq-exporter/orphan: instance directory without a matching installer unit",
		"mq-prometheus@.service: systemd template unit",
		"/usr/libexec/mq-prometheus/mq_prometheus: RPM package layout",
		"legacy-mq.service: unit not created by this installer",
	} {
		if !strings.Contains(all, want) {
			t.Errorf("missing %q in:\n%s", want, all)
		}
	}
}

func TestInventoryReportsForeignProcessesWithListeningPort(t *testing.T) {
	h := newHost(t)
	dest := h.instance("/opt/mq-exporter", "qm1", "mq_prometheus", "", "")
	h.write("/usr/local/lib/mqx-manual/mq_prometheus", "manual", 0o755)
	h.link("/proc/100/exe", "/usr/local/lib/mqx-manual/mq_prometheus")
	h.link("/proc/100/fd/3", "socket:[4242]")
	h.link("/proc/100/fd/4", "socket:[5555]")
	// A managed process whose binary was replaced on disk is not a foreign copy.
	h.link("/proc/200/exe", dest+"/mq_prometheus (deleted)")
	h.write("/proc/net/tcp", "  sl  local_address rem_address   st tx_queue rx_queue tr tm->when retrnsmt   uid  timeout inode\n"+
		"   0: 0100007F:23F7 00000000:0000 0A 00000000:00000000 00:00000000 00000000     0        0 4242 1\n"+
		"   1: 0100007F:1F90 0100007F:9C40 01 00000000:00000000 00:00000000 00000000     0        0 5555 1\n", 0o644)
	inv := scan(t, h, nil, nil)
	if len(inv.Instances) != 1 || len(inv.Unmanaged) != 1 {
		t.Fatalf("unexpected inventory: %+v", inv)
	}
	u := inv.Unmanaged[0]
	if u.Path != "/usr/local/lib/mqx-manual/mq_prometheus" || u.Port != "9207" || u.Version != "unrecorded" || u.SHA256 != sumOf("manual") || !strings.Contains(u.Reason, "pid 100") {
		t.Fatalf("foreign process report: %+v", u)
	}
	if !strings.HasPrefix(inv.TSV(), "managed\tqm1\t/opt/mq-exporter\t") {
		t.Fatalf("tsv: %q", inv.TSV())
	}
}
