#!/usr/bin/env bash

HOST="$(hostname)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"
FILTER="${1:-.*}"

printf 'HOST:      %s\n' "$HOST"
printf 'TIMESTAMP: %s\n' "$TIMESTAMP"
printf 'FILTER:    %s\n\n' "$FILTER"

printf "%-20s %14s %14s %12s %12s %12s %12s %12s %12s\n" \
    "INTERFACE" "RX_BYTES" "TX_BYTES" "RX_PACKETS" "TX_PACKETS" "RX_ERRORS" "TX_ERRORS" "RX_DROPS" "TX_DROPS"
printf '%*s\n' 142 '' | tr ' ' '-'

for path in /sys/class/net/*; do
    iface="${path##*/}"
    [ "$iface" = "lo" ] && continue

    if [[ ! "$iface" =~ $FILTER ]]; then
        continue
    fi

    stats="$path/statistics"
    [ -d "$stats" ] || continue

    read_stat() {
        local file="$1"
        local value="0"
        [ -r "$stats/$file" ] && read -r value < "$stats/$file"
        printf '%s' "$value"
    }

    printf "%-20s %14s %14s %12s %12s %12s %12s %12s %12s\n" \
        "$iface" \
        "$(read_stat rx_bytes)" \
        "$(read_stat tx_bytes)" \
        "$(read_stat rx_packets)" \
        "$(read_stat tx_packets)" \
        "$(read_stat rx_errors)" \
        "$(read_stat tx_errors)" \
        "$(read_stat rx_dropped)" \
        "$(read_stat tx_dropped)"
done
