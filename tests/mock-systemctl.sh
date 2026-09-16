#!/usr/bin/env bash
# Disposable-container fixture; not systemd lifecycle proof.
set -euo pipefail
case "$1" in daemon-reload|enable|restart) exit 0;; *) exit 1;; esac
