#!/usr/bin/env bash

HOST="$(hostname)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"

printf 'HOST:      %s\n' "$HOST"
printf 'TIMESTAMP: %s\n\n' "$TIMESTAMP"

if command -v ss >/dev/null 2>&1; then
    echo '=== LISTENING TCP/UDP SOCKETS ==='
    ss -lntup 2>/dev/null || ss -lntu 2>/dev/null || true
elif command -v netstat >/dev/null 2>&1; then
    echo '=== LISTENING TCP/UDP SOCKETS ==='
    netstat -lntup 2>/dev/null || netstat -lntu 2>/dev/null || true
else
    echo 'Neither ss nor netstat is available.'
    exit 1
fi
