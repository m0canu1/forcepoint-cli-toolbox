#!/usr/bin/env bash

HOST="$(hostname 2>/dev/null || cat /proc/sys/kernel/hostname 2>/dev/null || printf '%s' UNKNOWN)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || printf '%s' UNKNOWN)"
FILTER="${1:-.*}"

print_header() {
    printf "%-4s %-20s %-10s %-10s %-8s %-8s %-8s %-18s %-18s %-16s\n" \
        "#" "INTERFACE" "TYPE" "STATE" "CARRIER" "MTU" "SPEED" "DUPLEX" "MASTER" "DRIVER"
    printf '%s\n' "--------------------------------------------------------------------------------------------------------------------------------------------"
}

read_value() {
    local path="$1"
    local value="-"

    # Some virtual/tunnel sysfs attributes exist but return EINVAL when read.
    # Treat unsupported values as unavailable instead of printing kernel errors.
    if [ -r "$path" ]; then
        if ! IFS= read -r value < "$path" 2>/dev/null; then
            value="-"
        fi
        [ -z "$value" ] && value="-"
    fi

    printf '%s' "$value"
}

link_name() {
    local path="$1"
    local target=""
    if command -v readlink >/dev/null 2>&1; then
        target="$(readlink "$path" 2>/dev/null || true)"
    elif command -v busybox >/dev/null 2>&1; then
        target="$(busybox readlink "$path" 2>/dev/null || true)"
    fi
    [ -z "$target" ] && { printf '%s' "-"; return; }
    printf '%s' "${target##*/}"
}

print_interface() {
    local iface="$1"
    local num="$2"
    local base="/sys/class/net/$iface"
    local type="LOGICAL"
    local state carrier mtu speed duplex master driver

    [ -e "$base/device" ] && type="PHYSICAL"
    state="$(read_value "$base/operstate")"
    carrier="$(read_value "$base/carrier")"
    mtu="$(read_value "$base/mtu")"
    speed="$(read_value "$base/speed")"
    duplex="$(read_value "$base/duplex")"
    master="$(link_name "$base/master")"
    driver="$(link_name "$base/device/driver")"

    [ "$carrier" = "1" ] && carrier="UP"
    [ "$carrier" = "0" ] && carrier="DOWN"
    [ "$speed" = "-1" ] && speed="-"
    [ "$speed" != "-" ] && speed="${speed}M"

    printf "%-4s %-20s %-10s %-10s %-8s %-8s %-8s %-18s %-18s %-16s\n" \
        "$num" "$iface" "$type" "$state" "$carrier" "$mtu" "$speed" "$duplex" "$master" "$driver"
}

echo
printf '%s\n' "============================================================================================================================================"
printf ' HOST:      %s\n' "$HOST"
printf ' TIMESTAMP: %s\n' "$TIMESTAMP"
printf ' FILTER:    %s\n' "$FILTER"
printf '%s\n\n' "============================================================================================================================================"
print_header

count=1
found=0
for path in /sys/class/net/*; do
    iface="${path##*/}"
    [ "$iface" = "lo" ] && continue
    [[ "$iface" =~ $FILTER ]] || continue
    print_interface "$iface" "$count"
    count=$((count + 1))
    found=1
done

[ "$found" -eq 0 ] && echo "No matching interfaces found."
echo
