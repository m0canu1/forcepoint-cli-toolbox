#!/usr/bin/env bash

HOST="$(hostname)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"
FILTER="${1:-.*}"

printf 'HOST:      %s\n' "$HOST"
printf 'TIMESTAMP: %s\n' "$TIMESTAMP"
printf 'FILTER:    %s\n\n' "$FILTER"

printf "%-24s %-12s %-12s %-12s %-45s\n" "INTERFACE" "VLAN_ID" "PARENT" "STATE" "ADDRESSES"
printf '%*s\n' 112 '' | tr ' ' '-'

found=0
for path in /sys/class/net/*; do
    iface="${path##*/}"

    if [[ ! "$iface" =~ $FILTER ]]; then
        continue
    fi

    info="$(ip -d link show dev "$iface" 2>/dev/null)"
    vlan_id="$(printf '%s\n' "$info" | awk '/ vlan / {for (i=1; i<=NF; i++) if ($i=="id") {print $(i+1); exit}}')"
    [ -z "$vlan_id" ] && continue

    parent="$(printf '%s\n' "$info" | awk 'NR==1 {for (i=1; i<=NF; i++) if ($i ~ /@/) {split($i,a,"@"); print a[2]; exit}}')"
    [ -z "$parent" ] && parent="-"

    state="-"
    [ -r "$path/operstate" ] && read -r state < "$path/operstate"

    addresses="$(ip -o addr show dev "$iface" 2>/dev/null | awk '{printf "%s%s", (NR>1 ? "," : ""), $4}')"
    [ -z "$addresses" ] && addresses="-"

    printf "%-24s %-12s %-12s %-12s %-45s\n" "$iface" "$vlan_id" "$parent" "$state" "$addresses"
    found=1
done

if [ "$found" -eq 0 ]; then
    echo "No VLAN interfaces found."
fi
