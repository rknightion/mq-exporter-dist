#!/usr/bin/env bash
# Read-only; no hostnames, queue-manager inventory, environment dumps or secrets.
set -u
mq=${1:-/opt/mqm}
report() { local label=$1; shift; printf '%s: ' "$label"; if ! "$@" 2>/dev/null; then printf 'UNAVAILABLE\n'; fi; }
report architecture uname -m
report kernel uname -r
report glibc env LD_LIBRARY_PATH=/usr/lib64:/lib64 getconf GNU_LIBC_VERSION
report SELinux getenforce
if [[ -x $mq/bin/dspmqver ]]; then
  "$mq/bin/dspmqver" 2>/dev/null | awk '/^(Version|Level|Platform|Mode):/ {print}'
else printf 'MQ version: UNAVAILABLE (dspmqver missing)\n'; fi
if [[ -r $mq/lib64/libmqm_r.so ]]; then printf 'MQ 64-bit library: present\n'; else printf 'MQ 64-bit library: missing\n'; fi
printf 'Local bindings, MQ connection and service lifecycle: NOT TESTED\n'
