#!/usr/bin/env bash

HOST="$(hostname)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"

printf 'HOST:      %s\n' "$HOST"
printf 'TIMESTAMP: %s\n\n' "$TIMESTAMP"

if [ ! -d /proc/net/bonding ]; then
    echo 'No Linux bonding information found in /proc/net/bonding.'
    exit 0
fi

FOUND=0
for bond_file in /proc/net/bonding/*; do
    [ -f "$bond_file" ] || continue
    FOUND=1
    bond="${bond_file##*/}"
    printf '%s\n' "=== BOND: $bond ==="
    cat "$bond_file"
    echo
done

if [ "$FOUND" -eq 0 ]; then
    echo 'No active bonds found.'
fi
