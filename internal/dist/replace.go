package dist

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
)

// Replace stages on the destination filesystem and backs up by copying, never
// removing the installed file. A failed final rename leaves it in place.
func Replace(src, dst string) (string, error) {
	return replace(src, dst, io.Copy, os.Rename)
}

func replace(src, dst string, copyBytes func(io.Writer, io.Reader) (int64, error), rename func(string, string) error) (string, error) {
	in, e := os.Open(src)
	if e != nil {
		return "", e
	}
	defer in.Close()
	st, e := in.Stat()
	if e != nil {
		return "", e
	}
	if !st.Mode().IsRegular() {
		return "", fmt.Errorf("source is not regular")
	}
	out, e := os.CreateTemp(filepath.Dir(dst), ".mq-dist-stage-*")
	if e != nil {
		return "", e
	}
	temp := out.Name()
	defer os.Remove(temp)
	n, e := copyBytes(out, in)
	if e == nil && n != st.Size() {
		e = io.ErrShortWrite
	}
	if e == nil {
		e = out.Chmod(st.Mode().Perm())
	}
	if e == nil {
		e = out.Sync()
	}
	ce := out.Close()
	if e == nil {
		e = ce
	}
	if e != nil {
		return "", e
	}
	backup := ""
	old, e := os.Lstat(dst)
	if e == nil {
		if !old.Mode().IsRegular() {
			return "", fmt.Errorf("destination is not regular")
		}
		b, err := os.CreateTemp(filepath.Dir(dst), filepath.Base(dst)+".bak-*")
		if err != nil {
			return "", err
		}
		backup = b.Name()
		f, err := os.Open(dst)
		if err != nil {
			b.Close()
			return backup, err
		}
		_, err = copyBytes(b, f)
		f.Close()
		if err == nil {
			err = b.Chmod(old.Mode().Perm())
		}
		if err == nil {
			err = b.Sync()
		}
		ce = b.Close()
		if err == nil {
			err = ce
		}
		if err != nil {
			return backup, err
		}
	} else if !os.IsNotExist(e) {
		return "", e
	}
	if e = rename(temp, dst); e != nil {
		return backup, e
	}
	return backup, nil
}
