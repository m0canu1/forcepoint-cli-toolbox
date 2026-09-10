#!/usr/bin/env bash

HOST="$(hostname)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"

printf 'HOST:      %s\n' "$HOST"
printf 'TIMESTAMP: %s\n\n' "$TIMESTAMP"

echo '=== POLICY ROUTING RULES ==='
ip rule show 2>/dev/null || true

echo

echo '=== MAIN ROUTING TABLE ==='
ip route show table main 2>/dev/null || true

echo

echo '=== REFERENCED ROUTING TABLES ==='

TABLES="$(
    ip rule show 2>/dev/null |
        awk '
            {
                for (i = 1; i <= NF; i++) {
                    if ($i == "lookup" && (i + 1) <= NF) {
                        print $(i + 1)
                    }
                }
            }
        ' |
        awk '!seen[$0]++'
)"

if [ -z "$TABLES" ]; then
    echo 'No routing tables referenced by policy rules.'
    exit 0
fi

while IFS= read -r table; do
    case "$table" in
        local|main|default)
            continue
            ;;
    esac

    echo
    printf '%s\n' "--- TABLE: $table ---"
    ip route show table "$table" 2>/dev/null || true
done <<EOF
$TABLES
EOF
