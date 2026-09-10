#!/usr/bin/env bash

HOST="$(hostname)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"
DESTINATION="${1:-}"
SOURCE="${2:-}"

if [ -z "$DESTINATION" ]; then
    echo "Usage: $0 <destination-ip> [source-ip]"
    exit 1
fi

printf 'HOST:        %s\n' "$HOST"
printf 'TIMESTAMP:   %s\n' "$TIMESTAMP"
printf 'DESTINATION: %s\n' "$DESTINATION"
[ -n "$SOURCE" ] && printf 'SOURCE:      %s\n' "$SOURCE"
printf '\n'

echo '=== ROUTING DECISION ==='
if [ -n "$SOURCE" ]; then
    ip route get "$DESTINATION" from "$SOURCE" 2>&1
else
    ip route get "$DESTINATION" 2>&1
fi

printf '\n=== POLICY ROUTING RULES ===\n'
ip rule show 2>/dev/null || true

printf '\n=== RELEVANT NEIGHBOURS ===\n'
route_output="$(ip route get "$DESTINATION" ${SOURCE:+from "$SOURCE"} 2>/dev/null)"
dev="$(printf '%s\n' "$route_output" | awk '{for (i=1; i<=NF; i++) if ($i=="dev") {print $(i+1); exit}}')"
gw="$(printf '%s\n' "$route_output" | awk '{for (i=1; i<=NF; i++) if ($i=="via") {print $(i+1); exit}}')"

if [ -n "$gw" ]; then
    ip neigh show to "$gw" ${dev:+dev "$dev"} 2>/dev/null || true
elif [ -n "$dev" ]; then
    ip neigh show dev "$dev" 2>/dev/null || true
else
    echo "Unable to determine egress interface."
fi
