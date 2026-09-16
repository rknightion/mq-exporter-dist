package dist

import (
	"encoding/binary"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRejectWrongArchitectureAndGLIBCFloor(t *testing.T) {
	for _, tc := range []struct {
		machine    uint16
		tail, want string
	}{{183, "", "x86-64"}, {62, "GLIBC_2.29", "2.28"}} {
		b := make([]byte, 64)
		copy(b, []byte{0x7f, 'E', 'L', 'F', 2, 1, 1})
		binary.LittleEndian.PutUint16(b[16:], 2)
		binary.LittleEndian.PutUint16(b[18:], tc.machine)
		binary.LittleEndian.PutUint32(b[20:], 1)
		binary.LittleEndian.PutUint16(b[52:], 64)
		p := filepath.Join(t.TempDir(), "candidate")
		if e := os.WriteFile(p, append(b, []byte(tc.tail)...), 0600); e != nil {
			t.Fatal(e)
		}
		e := Inspect(p, "linux")
		if e == nil || !strings.Contains(e.Error(), tc.want) {
			t.Fatalf("expected %s rejection, got %v", tc.want, e)
		}
	}
}
