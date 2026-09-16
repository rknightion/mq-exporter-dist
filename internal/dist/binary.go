package dist

import (
	"debug/elf"
	"debug/pe"
	"fmt"
	"io"
	"os"
	"regexp"
	"strconv"
)

func Inspect(filename, platform string) error {
	if platform == "windows" {
		f, e := pe.Open(filename)
		if e != nil {
			return e
		}
		defer f.Close()
		if f.Machine != pe.IMAGE_FILE_MACHINE_AMD64 {
			return fmt.Errorf("expected PE amd64")
		}
		return nil
	}
	f, e := elf.Open(filename)
	if e != nil {
		return e
	}
	defer f.Close()
	if f.Machine != elf.EM_X86_64 || f.Class != elf.ELFCLASS64 {
		return fmt.Errorf("expected ELF x86-64")
	}
	if paths, _ := f.DynString(elf.DT_RPATH); len(paths) > 0 {
		return fmt.Errorf("DT_RPATH prevents configured MQ override; use RUNPATH")
	}
	for _, p := range f.Progs {
		if p.Type == elf.PT_INTERP {
			b, e := io.ReadAll(p.Open())
			if e != nil {
				return e
			}
			if string(b) != "/lib64/ld-linux-x86-64.so.2\x00" {
				return fmt.Errorf("unexpected ELF interpreter")
			}
		}
	}
	b, e := os.ReadFile(filename)
	if e != nil {
		return e
	}
	re := regexp.MustCompile(`GLIBC_([0-9]+)\.([0-9]+)`)
	for _, m := range re.FindAllSubmatch(b, -1) {
		major, _ := strconv.Atoi(string(m[1]))
		minor, _ := strconv.Atoi(string(m[2]))
		if major > 2 || (major == 2 && minor > 28) {
			return fmt.Errorf("GLIBC requirement exceeds 2.28")
		}
	}
	return nil
}
