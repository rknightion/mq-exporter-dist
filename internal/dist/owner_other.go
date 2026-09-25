//go:build !unix

package dist

import "os"

// The inventory only runs on Linux; other builds of mq-dist never call it.
func fileOwner(os.FileInfo) (uint32, bool) { return 0, false }
