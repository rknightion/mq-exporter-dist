package dist

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"testing"
)

func TestPartialCopyBackupAndMoveFailures(t *testing.T) {
	for _, stage := range []string{"copy", "backup", "rename"} {
		t.Run(stage, func(t *testing.T) {
			d := t.TempDir()
			src := filepath.Join(d, "new")
			dst := filepath.Join(d, "installed")
			_ = os.WriteFile(src, []byte("new bytes"), 0600)
			_ = os.WriteFile(dst, []byte("old bytes"), 0600)
			calls := 0
			copier := func(w io.Writer, r io.Reader) (int64, error) {
				calls++
				if (stage == "copy" && calls == 1) || (stage == "backup" && calls == 2) {
					n, _ := w.Write([]byte("partial"))
					return int64(n), io.ErrShortWrite
				}
				return io.Copy(w, r)
			}
			rename := func(a, b string) error {
				if stage == "rename" {
					return fmt.Errorf("injected rename failure")
				}
				return os.Rename(a, b)
			}
			if _, e := replace(src, dst, copier, rename); e == nil {
				t.Fatal("failure swallowed")
			}
			b, _ := os.ReadFile(dst)
			if string(b) != "old bytes" {
				t.Fatal("installed executable lost")
			}
		})
	}
}

func TestReplaceSafety(t *testing.T) {
	d := t.TempDir()
	dst := filepath.Join(d, "installed")
	src := filepath.Join(d, "candidate")
	if e := os.WriteFile(dst, []byte("old"), 0600); e != nil {
		t.Fatal(e)
	}
	if _, e := Replace(src, dst); e == nil {
		t.Fatal("missing input accepted")
	}
	b, _ := os.ReadFile(dst)
	if string(b) != "old" {
		t.Fatal("old lost")
	}
	_ = os.WriteFile(src, []byte("new"), 0600)
	backup, e := Replace(src, dst)
	if e != nil {
		t.Fatal(e)
	}
	b, _ = os.ReadFile(backup)
	if string(b) != "old" {
		t.Fatal("backup lost")
	}
	b, _ = os.ReadFile(dst)
	if string(b) != "new" {
		t.Fatal("not replaced")
	}
	second, e := Replace(src, dst)
	if e != nil || second == backup {
		t.Fatal("backup collision", e)
	}
	if _, e = Replace(src, d); e == nil {
		t.Fatal("directory replaced")
	}
}
