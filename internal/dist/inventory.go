package dist

import (
	"bufio"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"os"
	"path"
	"path/filepath"
	"regexp"
	"sort"
	"strconv"
	"strings"
	"syscall"
)

// Instance is an installer-managed exporter that the updater may replace.
type Instance struct {
	Name, Root, Dest, Unit, Exporter, Variant, Binary string
	Version, SHA256, Port, QMgr                       string
}

// Unmanaged is an exporter copy the updater must report but never touch.
type Unmanaged struct {
	Path, Version, SHA256, Port, Reason string
}

type Inventory struct {
	Instances []Instance
	Unmanaged []Unmanaged
}

// KnownRelease maps published payload hashes to their release identity.
type KnownRelease struct {
	Tag      string            `json:"tag"`
	Exporter string            `json:"exporter"`
	Variant  string            `json:"variant"`
	Platform string            `json:"platform"`
	Payload  map[string]string `json:"payload_sha256"`
}

var exporterBinaries = map[string]string{"mq_prometheus": "prometheus", "mq_prometheus_custom": "prometheus", "mq_otel": "otel"}
var managedUnit = regexp.MustCompile(`^mq-exporter-([a-z][a-z0-9-]{0,39})\.service$`)
var managedExec = regexp.MustCompile(`^"(/[^"]+)/(mq_prometheus|mq_prometheus_custom|mq_otel)" -f "(/[^"]+)/config\.json"$`)
var exporterReference = regexp.MustCompile(`mq_prometheus|mq_otel`)

var unitDirs = []string{"/etc/systemd/system", "/run/systemd/system", "/usr/lib/systemd/system"}
var packagedPaths = []string{"/usr/libexec/mq-prometheus/mq_prometheus", "/usr/libexec/mq-otel/mq_otel"}

// Scanner resolves every path under Sysroot so tests can use a synthetic host.
type Scanner struct {
	Sysroot string
	Roots   []string
	Known   []KnownRelease
	// OwnerUID is the required owner; zero (root) outside tests.
	OwnerUID uint32
}

func (s Scanner) host(p string) string { return filepath.Join(s.Sysroot, p) }

// trusted accepts a canonical, root-owned, non-symlink path that is not
// group/world writable. Ancestors are checked by the installer preflight.
func (s Scanner) trusted(p string, dir bool) error {
	fi, e := os.Lstat(s.host(p))
	if e != nil {
		return e
	}
	if fi.Mode()&os.ModeSymlink != 0 {
		return fmt.Errorf("symlink")
	}
	if dir != fi.IsDir() || (!dir && !fi.Mode().IsRegular()) {
		return fmt.Errorf("unexpected file type")
	}
	if fi.Mode().Perm()&0o022 != 0 {
		return fmt.Errorf("group/world writable")
	}
	if st, ok := fi.Sys().(*syscall.Stat_t); ok && st.Uid != s.OwnerUID {
		return fmt.Errorf("not root-owned")
	}
	if r, e := filepath.EvalSymlinks(s.host(p)); e != nil || r != s.host(p) {
		return fmt.Errorf("noncanonical path")
	}
	return nil
}

func (s Scanner) sum(p string) string {
	f, e := os.Open(s.host(p))
	if e != nil {
		return ""
	}
	defer f.Close()
	h := sha256.New()
	if _, e = io.Copy(h, f); e != nil {
		return ""
	}
	return hex.EncodeToString(h.Sum(nil))
}

// version names a binary from its release record, then published hashes.
func (s Scanner) version(dir, binary, sum string) string {
	if b, e := os.ReadFile(s.host(path.Join(dir, "release"))); e == nil {
		lines := strings.Split(string(b), "\n")
		if len(lines) >= 5 && lines[4] == sum {
			if _, e := ParseVersion(lines[0]); e == nil {
				return lines[0]
			}
		}
	}
	for _, k := range s.Known {
		if k.Platform == "linux-amd64" && sum != "" && k.Payload[binary] == sum {
			return k.Tag
		}
	}
	return "unrecorded"
}

func execStart(unit []byte) []string {
	out := []string{}
	sc := bufio.NewScanner(strings.NewReader(string(unit)))
	for sc.Scan() {
		l := strings.TrimSpace(sc.Text())
		if strings.HasPrefix(l, "ExecStart=") {
			out = append(out, strings.TrimPrefix(l, "ExecStart="))
		}
	}
	return out
}

func (s Scanner) dropInsOverrideExec(unit string) bool {
	for _, d := range unitDirs {
		matches, _ := filepath.Glob(s.host(path.Join(d, unit+".d", "*.conf")))
		for _, m := range matches {
			if b, e := os.ReadFile(m); e == nil && len(execStart(b)) > 0 {
				return true
			}
		}
	}
	return false
}

func (s Scanner) managed(unit string) (Instance, string) {
	name := managedUnit.FindStringSubmatch(unit)[1]
	file := path.Join("/etc/systemd/system", unit)
	if e := s.trusted(file, false); e != nil {
		return Instance{}, "unit file rejected: " + e.Error()
	}
	b, e := os.ReadFile(s.host(file))
	if e != nil {
		return Instance{}, "unit unreadable"
	}
	lines := execStart(b)
	if len(lines) != 1 {
		return Instance{}, "unit does not have exactly one ExecStart"
	}
	m := managedExec.FindStringSubmatch(lines[0])
	if m == nil || m[1] != m[3] || path.Base(m[1]) != name || path.Clean(m[1]) != m[1] {
		return Instance{}, "ExecStart is not the installer layout"
	}
	if s.dropInsOverrideExec(unit) {
		return Instance{}, "drop-in overrides ExecStart"
	}
	dest := m[1]
	for _, p := range []struct {
		p   string
		dir bool
	}{{dest, true}, {path.Join(dest, "identity"), false}, {path.Join(dest, m[2]), false}} {
		if e := s.trusted(p.p, p.dir); e != nil {
			return Instance{}, p.p + " rejected: " + e.Error()
		}
	}
	id, _ := os.ReadFile(s.host(path.Join(dest, "identity")))
	fields := strings.Split(strings.TrimSuffix(string(id), "\n"), "\n")
	if len(fields) < 8 {
		return Instance{}, "identity record incomplete"
	}
	variant := "native"
	if b, e := os.ReadFile(s.host(path.Join(dest, "variant"))); e == nil {
		variant = strings.TrimSpace(string(b))
	}
	want := map[string]string{"mq_prometheus": "native", "mq_otel": "native", "mq_prometheus_custom": "custom"}[m[2]]
	if variant != want {
		return Instance{}, "variant record does not match the unit binary"
	}
	sum := s.sum(path.Join(dest, m[2]))
	return Instance{Name: name, Root: path.Dir(dest), Dest: dest, Unit: unit, Exporter: exporterBinaries[m[2]], Variant: variant,
		Binary: m[2], Version: s.version(dest, m[2], sum), SHA256: sum, Port: fields[1], QMgr: fields[0]}, ""
}

// listeners maps socket inodes to TCP listening ports.
func (s Scanner) listeners() map[string]string {
	out := map[string]string{}
	for _, f := range []string{"/proc/net/tcp", "/proc/net/tcp6"} {
		b, e := os.ReadFile(s.host(f))
		if e != nil {
			continue
		}
		for i, l := range strings.Split(string(b), "\n") {
			x := strings.Fields(l)
			if i == 0 || len(x) < 10 || x[3] != "0A" {
				continue
			}
			local := strings.Split(x[1], ":")
			if p, e := strconv.ParseInt(local[len(local)-1], 16, 32); e == nil {
				out[x[9]] = strconv.FormatInt(p, 10)
			}
		}
	}
	return out
}

func (s Scanner) processPort(pid string, sockets map[string]string) string {
	fds, _ := os.ReadDir(s.host(path.Join("/proc", pid, "fd")))
	ports := []string{}
	for _, fd := range fds {
		t, e := os.Readlink(s.host(path.Join("/proc", pid, "fd", fd.Name())))
		if e == nil && strings.HasPrefix(t, "socket:[") {
			if p, ok := sockets[strings.TrimSuffix(strings.TrimPrefix(t, "socket:["), "]")]; ok {
				ports = append(ports, p)
			}
		}
	}
	sort.Strings(ports)
	if len(ports) == 0 {
		return "unknown"
	}
	return strings.Join(ports, ",")
}

func (s Scanner) Scan() (Inventory, error) {
	inv := Inventory{}
	dests := map[string]bool{}
	seen := map[string]bool{}
	report := func(u Unmanaged) {
		key := u.Path + "\x00" + u.Reason
		if !seen[key] {
			seen[key] = true
			inv.Unmanaged = append(inv.Unmanaged, u)
		}
	}
	for _, dir := range unitDirs {
		entries, _ := os.ReadDir(s.host(dir))
		for _, e := range entries {
			name := e.Name()
			if !strings.HasSuffix(name, ".service") {
				continue
			}
			if dir == "/etc/systemd/system" && managedUnit.MatchString(name) {
				if i, why := s.managed(name); why == "" {
					inv.Instances = append(inv.Instances, i)
					dests[i.Dest] = true
				} else {
					report(Unmanaged{Path: path.Join(dir, name), Version: "unrecorded", Port: "unknown", Reason: why})
				}
				continue
			}
			b, err := os.ReadFile(s.host(path.Join(dir, name)))
			if err != nil || !exporterReference.Match(b) {
				continue
			}
			reason := "unit not created by this installer"
			if strings.Contains(name, "@") {
				reason = "systemd template unit (RPM layout); update it with the package manager"
			}
			report(Unmanaged{Path: path.Join(dir, name), Version: "unrecorded", Port: "unknown", Reason: reason})
		}
	}
	for _, p := range packagedPaths {
		if _, e := os.Lstat(s.host(p)); e == nil {
			sum := s.sum(p)
			report(Unmanaged{Path: p, Version: s.version(path.Dir(p), path.Base(p), sum), SHA256: sum, Port: "unknown", Reason: "RPM package layout; update it with the package manager"})
		}
	}
	for _, root := range s.Roots {
		matches, _ := filepath.Glob(s.host(path.Join(root, "*", "identity")))
		for _, m := range matches {
			dest := path.Dir(strings.TrimPrefix(m, s.Sysroot))
			if !dests[dest] {
				report(Unmanaged{Path: dest, Version: "unrecorded", Port: "unknown", Reason: "instance directory without a matching installer unit"})
			}
		}
	}
	sockets := s.listeners()
	procs, _ := os.ReadDir(s.host("/proc"))
	for _, p := range procs {
		if _, e := strconv.Atoi(p.Name()); e != nil {
			continue
		}
		exe, e := os.Readlink(s.host(path.Join("/proc", p.Name(), "exe")))
		if e != nil {
			continue
		}
		clean := strings.TrimSuffix(exe, " (deleted)")
		if _, ok := exporterBinaries[path.Base(clean)]; !ok || dests[path.Dir(clean)] {
			continue
		}
		sum := s.sum(clean)
		report(Unmanaged{Path: clean, Version: s.version(path.Dir(clean), path.Base(clean), sum), SHA256: sum, Port: s.processPort(p.Name(), sockets), Reason: "running process outside the managed layout (pid " + p.Name() + ")"})
	}
	sort.Slice(inv.Instances, func(a, b int) bool { return inv.Instances[a].Dest < inv.Instances[b].Dest })
	return inv, nil
}

// LoadKnown reads the known-releases table shipped in each Linux archive.
func LoadKnown(file string) ([]KnownRelease, error) {
	if file == "" {
		return nil, nil
	}
	b, e := os.ReadFile(file)
	if e != nil {
		return nil, e
	}
	var k []KnownRelease
	return k, json.Unmarshal(b, &k)
}

// TSV output is consumed by update.sh; fields never contain tabs or newlines.
func (inv Inventory) TSV() string {
	var b strings.Builder
	clean := func(v string) string {
		if v == "" {
			return "-"
		}
		return strings.NewReplacer("\t", " ", "\n", " ").Replace(v)
	}
	for _, i := range inv.Instances {
		fmt.Fprintln(&b, strings.Join([]string{"managed", i.Name, i.Root, i.Dest, i.Unit, i.Exporter, i.Variant, i.Binary, clean(i.Version), clean(i.SHA256), clean(i.Port), clean(i.QMgr)}, "\t"))
	}
	for _, u := range inv.Unmanaged {
		fmt.Fprintln(&b, strings.Join([]string{"unmanaged", clean(u.Path), clean(u.Version), clean(u.SHA256), clean(u.Port), clean(u.Reason)}, "\t"))
	}
	return b.String()
}
