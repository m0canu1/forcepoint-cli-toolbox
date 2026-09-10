#!/usr/bin/env bash

HOST="$(hostname)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"
FILTER="${1:-^(vpn|tun|tap|ipsec|vti)}"

printf 'HOST:      %s\n' "$HOST"
printf 'TIMESTAMP: %s\n' "$TIMESTAMP"
printf 'FILTER:    %s\n\n' "$FILTER"

echo '=== VPN-RELATED ROUTES ==='

found=0
while IFS= read -r line; do
    iface="$(printf '%s\n' "$line" | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"
    [ -z "$iface" ] && continue

    if [[ "$iface" =~ $FILTER ]]; then
        printf '%s\n' "$line"
        found=1
    fi
done < <(ip route show table all 2>/dev/null)

if [ "$found" -eq 0 ]; then
    echo 'No matching VPN-related routes found.'
fi
