#!/usr/bin/env bash
# Disposable container fixture; never installed on a target server.
printf '%s\n' "$*" >> /tmp/rpm-systemctl-calls
