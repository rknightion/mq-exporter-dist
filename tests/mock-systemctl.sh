#!/usr/bin/env bash
# Disposable-container fixture; not systemd lifecycle proof. Keeps per-unit
# state and runs ExecStart directly so MainPID and /proc/PID/exe are real.
set -euo pipefail
state=/run/mock-systemd
mkdir -p "$state"
unit_file() { printf '/etc/systemd/system/%s' "$1"; }
pid_of() { local p; p=$(cat "$state/$1.pid" 2>/dev/null || true); [[ -n $p ]] && kill -0 "$p" 2>/dev/null && printf '%s' "$p"; }
start() {
  local u=$1 exec bin cfg env
  [[ -z $(pid_of "$u") ]] || return 0
  exec=$(sed -n 's/^ExecStart=//p' "$(unit_file "$u")")
  env=$(sed -n 's/^Environment="LD_LIBRARY_PATH=\(.*\)"$/\1/p' "$(unit_file "$u")")
  bin=$(sed -E 's/^"([^"]+)" -f "([^"]+)"$/\1/' <<< "$exec")
  cfg=$(sed -E 's/^"([^"]+)" -f "([^"]+)"$/\2/' <<< "$exec")
  # Like systemd, never hand the caller's lock descriptors to the service.
  LD_LIBRARY_PATH=$env setsid "$bin" -f "$cfg" > "$state/$u.log" 2>&1 < /dev/null 8>&- 9>&- &
  printf '%s' "$!" > "$state/$u.pid"
}
stop() {
  local u=$1 p
  p=$(pid_of "$u") || true
  if [[ -n $p ]]; then kill "$p"; while kill -0 "$p" 2>/dev/null; do sleep 0.1; done; fi
  rm -f "$state/$u.pid"
}
cmd=$1; shift
case "$cmd" in
  daemon-reload) exit 0;;
  enable) printf enabled > "$state/$1.enabled";;
  disable) printf disabled > "$state/$1.enabled";;
  is-enabled) s=$(cat "$state/$1.enabled" 2>/dev/null || printf disabled); printf '%s\n' "$s"; [[ $s == enabled ]];;
  is-active) if [[ -n $(pid_of "$1") ]]; then printf 'active\n'; else printf 'inactive\n'; exit 3; fi;;
  start) start "$1";;
  stop) stop "$1";;
  restart) stop "$1"; start "$1";;
  show)
    u=$1 prop=$3
    case "$prop" in
      MainPID) p=$(pid_of "$u") || true; printf '%s\n' "${p:-0}";;
      NRestarts) printf '0\n';;
      ActiveState) if [[ -n $(pid_of "$u") ]]; then printf 'active\n'; else printf 'inactive\n'; fi;;
      *) exit 1;;
    esac;;
  *) exit 1;;
esac
