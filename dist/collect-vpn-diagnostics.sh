#!/usr/bin/env bash

HOST="$(hostname)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"
FILTER="${1:-^(vpn|tun|tap|ipsec|vti)}"

section() {
    printf '\n=== %s ===\n' "$1"
}

printf 'HOST:      %s\n' "$HOST"
printf 'TIMESTAMP: %s\n' "$TIMESTAMP"
printf 'FILTER:    %s\n' "$FILTER"

section 'VPN-LIKE INTERFACES'
for path in /sys/class/net/*; do
    iface="${path##*/}"
    [[ "$iface" =~ $FILTER ]] || continue
    ip -d addr show dev "$iface" 2>/dev/null || true
done

section 'VPN-RELATED ROUTES'
while IFS= read -r line; do
    iface="$(printf '%s\n' "$line" | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"
    [ -n "$iface" ] && [[ "$iface" =~ $FILTER ]] && printf '%s\n' "$line"
done < <(ip route show table all 2>/dev/null)

section 'POLICY ROUTING RULES'
ip rule show 2>/dev/null || true

section 'NEIGHBOURS ON VPN-LIKE INTERFACES'
for path in /sys/class/net/*; do
    iface="${path##*/}"
    [[ "$iface" =~ $FILTER ]] || continue
    echo "-- $iface --"
    ip neigh show dev "$iface" 2>/dev/null || true
done

section 'XFRM STATE'
if ip xfrm state >/dev/null 2>&1; then
    ip xfrm state 2>/dev/null || true
else
    echo 'XFRM state information is unavailable.'
fi

section 'XFRM POLICY'
if ip xfrm policy >/dev/null 2>&1; then
    ip xfrm policy 2>/dev/null || true
else
    echo 'XFRM policy information is unavailable.'
fi
