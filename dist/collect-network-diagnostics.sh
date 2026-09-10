#!/usr/bin/env bash

HOST="$(hostname)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"

section() {
    echo
    printf '=== %s ===\n' "$1"
}

printf 'HOST:      %s\n' "$HOST"
printf 'TIMESTAMP: %s\n' "$TIMESTAMP"

section 'INTERFACES'
ip -brief addr show 2>/dev/null || ip addr show 2>/dev/null || true

section 'LINKS'
ip -brief link show 2>/dev/null || ip link show 2>/dev/null || true

section 'POLICY ROUTING RULES'
ip rule show 2>/dev/null || true

section 'MAIN ROUTING TABLE'
ip route show table main 2>/dev/null || true

section 'NEIGHBOURS'
ip neigh show 2>/dev/null || true

section 'LISTENING SOCKETS'
if command -v ss >/dev/null 2>&1; then
    ss -lntup 2>/dev/null || ss -lntu 2>/dev/null || true
elif command -v netstat >/dev/null 2>&1; then
    netstat -lntup 2>/dev/null || netstat -lntu 2>/dev/null || true
else
    echo 'Neither ss nor netstat is available.'
fi

section 'BONDING'
if [ -d /proc/net/bonding ]; then
    found=0
    for bond_file in /proc/net/bonding/*; do
        [ -f "$bond_file" ] || continue
        found=1
        printf '%s\n' "--- ${bond_file##*/} ---"
        cat "$bond_file"
    done
    [ "$found" -eq 0 ] && echo 'No active bonds found.'
else
    echo 'No Linux bonding information found.'
fi

section 'KERNEL NETWORK MESSAGES'
if command -v dmesg >/dev/null 2>&1; then
    dmesg 2>/dev/null | tail -n 100 || true
else
    echo 'dmesg is not available.'
fi
