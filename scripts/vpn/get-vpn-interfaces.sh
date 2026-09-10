#!/usr/bin/env bash

HOST="$(hostname)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"
FILTER="${1:-^(vpn|tun|tap|ipsec|vti)}"

printf 'HOST:      %s\n' "$HOST"
printf 'TIMESTAMP: %s\n' "$TIMESTAMP"
printf 'FILTER:    %s\n\n' "$FILTER"

printf "%-20s %-10s %-10s %-8s %-45s\n" "INTERFACE" "STATE" "MTU" "TYPE" "ADDRESSES"
printf '%*s\n' 100 '' | tr ' ' '-'

for path in /sys/class/net/*; do
    iface="${path##*/}"

    if [[ ! "$iface" =~ $FILTER ]]; then
        continue
    fi

    state="-"
    mtu="-"
    type="logical"
    addresses="-"

    [ -r "$path/operstate" ] && read -r state < "$path/operstate"
    [ -r "$path/mtu" ] && read -r mtu < "$path/mtu"
    [ -e "$path/device" ] && type="physical"

    addr_out="$(ip -o addr show dev "$iface" 2>/dev/null | awk '{printf "%s%s", (NR>1 ? "," : ""), $4}')"
    [ -n "$addr_out" ] && addresses="$addr_out"

    printf "%-20s %-10s %-10s %-8s %-45s\n" "$iface" "$state" "$mtu" "$type" "$addresses"
done
