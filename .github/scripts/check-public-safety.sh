#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/../.." && pwd)"
cd "$ROOT_DIR"

failed=0

printf '%s\n' 'Checking repository layout...'
if [ -e scripts ]; then
    echo 'Unexpected top-level scripts/ directory found. dist/ is the canonical script location.' >&2
    failed=1
fi

printf '%s\n' 'Checking dist script permissions...'
for script in dist/*.sh; do
    [ -f "$script" ] || continue
    if [ ! -x "$script" ]; then
        echo "Not executable: $script" >&2
        failed=1
    fi
done

printf '%s\n' 'Checking for sensitive file types...'
sensitive_files="$(
    find . -path './.git' -prune -o -type f \( \
        -name '.env' -o -name '.env.*' -o \
        -name '*.key' -o -name '*.pem' -o -name '*.p12' -o -name '*.pfx' -o \
        -name '*.jks' -o -name '*.kdb' -o \
        -name '*.pcap' -o -name '*.pcapng' -o -name '*.cap' \
    \) -print
)"

if [ -n "$sensitive_files" ]; then
    echo 'Sensitive file types found:' >&2
    printf '%s\n' "$sensitive_files" >&2
    failed=1
fi

printf '%s\n' 'Checking for obvious secret material...'
if grep -RInE \
    --exclude-dir=.git \
    --exclude='check-public-safety.sh' \
    '(-----BEGIN ([A-Z0-9 ]+ )?PRIVATE KEY-----|github_pat_[A-Za-z0-9_]+|gh[pousr]_[A-Za-z0-9]{20,}|AKIA[0-9A-Z]{16}|xox[baprs]-[A-Za-z0-9-]+|AIza[0-9A-Za-z_-]{30,})' \
    .; then
    echo 'Potential secret material found.' >&2
    failed=1
fi

printf '%s\n' 'Checking that dist scripts are standalone...'
if grep -nE '(source|\.)[[:space:]]+.*(\.\./|/lib/|compat\.sh)' dist/*.sh 2>/dev/null; then
    echo 'A dist script appears to source another repository-local file.' >&2
    failed=1
fi

printf '%s\n' 'Checking read-only policy for dist scripts...'
if grep -nE \
    '(^|[;&|[:space:]])(reboot|poweroff|halt|shutdown)([;&|[:space:]]|$)|ip[[:space:]]+(link[[:space:]]+set|addr[[:space:]]+(add|del|delete|flush)|route[[:space:]]+(add|del|delete|replace|flush)|rule[[:space:]]+(add|del|delete))|sysctl[[:space:]]+-w|iptables[[:space:]].*[[:space:]](-A|-I|-D|-F|-X|-P)([[:space:]]|$)|nft[[:space:]]+(add|delete|flush)|systemctl[[:space:]]+(stop|restart|disable|mask)|service[[:space:]].*[[:space:]](stop|restart)' \
    dist/*.sh 2>/dev/null; then
    echo 'Potential mutating command found in dist/.' >&2
    failed=1
fi

if [ "$failed" -ne 0 ]; then
    exit 1
fi

echo 'Public-safety checks passed.'
