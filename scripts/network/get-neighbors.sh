#!/usr/bin/env bash

HOST="$(hostname)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"
FILTER="${1:-.*}"

printf 'HOST:      %s\n' "$HOST"
printf 'TIMESTAMP: %s\n' "$TIMESTAMP"
printf 'FILTER:    %s\n\n' "$FILTER"

echo '=== IPv4 / IPv6 NEIGHBOURS ==='

ip neigh show 2>/dev/null |
    awk -v filter="$FILTER" '
        {
            iface = ""
            for (i = 1; i <= NF; i++) {
                if ($i == "dev" && (i + 1) <= NF) {
                    iface = $(i + 1)
                    break
                }
            }

            if (iface == "" || iface ~ filter) {
                print
            }
        }
    '
