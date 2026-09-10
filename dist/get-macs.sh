#!/usr/bin/env bash

busybox_bin=""
if command -v busybox >/dev/null 2>&1; then
    busybox_bin="$(command -v busybox 2>/dev/null)"
fi

has_cmd() {
    command -v "$1" >/dev/null 2>&1 && return 0
    [ -n "$busybox_bin" ] && "$busybox_bin" --list 2>/dev/null | grep -qx "$1"
}

run_cmd() {
    local cmd="$1"
    shift

    if command -v "$cmd" >/dev/null 2>&1; then
        "$cmd" "$@"
        return $?
    fi

    if [ -n "$busybox_bin" ] && "$busybox_bin" --list 2>/dev/null | grep -qx "$cmd"; then
        "$busybox_bin" "$cmd" "$@"
        return $?
    fi

    return 127
}

get_hostname() {
    local value=""
    if has_cmd hostname; then
        value="$(run_cmd hostname 2>/dev/null || true)"
    fi
    if [ -z "$value" ] && [ -r /proc/sys/kernel/hostname ]; then
        read -r value < /proc/sys/kernel/hostname || value=""
    fi
    [ -z "$value" ] && value="UNKNOWN"
    printf '%s' "$value"
}

get_timestamp() {
    local value=""
    if has_cmd date; then
        value="$(run_cmd date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || true)"
    fi
    [ -z "$value" ] && value="UNKNOWN"
    printf '%s' "$value"
}

natural_sort() {
    if command -v sort >/dev/null 2>&1; then
        if sort -V </dev/null >/dev/null 2>&1; then
            sort -V
        else
            sort
        fi
    elif [ -n "$busybox_bin" ] && "$busybox_bin" --list 2>/dev/null | grep -qx sort; then
        if "$busybox_bin" sort -V </dev/null >/dev/null 2>&1; then
            "$busybox_bin" sort -V
        else
            "$busybox_bin" sort
        fi
    else
        cat
    fi
}

HOST="$(get_hostname)"
TIMESTAMP="$(get_timestamp)"
FILTER="${1:-.*}"

ETHTOOL_AVAILABLE=false
if has_cmd ethtool; then
    ETHTOOL_AVAILABLE=true
fi

SEPARATOR="========================================================================================================================================================================================================================================"
DASH_SEPARATOR="----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------"

print_title() {
    echo
    printf '%s\n' "$SEPARATOR"
    printf ' HOST:      %s\n' "$HOST"
    printf ' TIMESTAMP: %s\n' "$TIMESTAMP"
    printf ' FILTER:    %s\n' "$FILTER"
    printf '%s\n' "$SEPARATOR"
}

print_header() {
    printf "%-4s %-20s %-10s %-20s %-20s %-8s %-80s %-50s\n" \
        "#" "INTERFACE" "STATE" "CURRENT MAC" "PERMANENT MAC" "MATCH" "IPv4" "IPv6"
    printf '%s\n' "$DASH_SEPARATOR"
}

interface_matches_filter() {
    local iface="$1"
    [[ "$iface" =~ $FILTER ]]
}

get_ipv4() {
    local iface="$1"
    run_cmd ip -o -4 addr show dev "$iface" 2>/dev/null |
        run_cmd awk '{printf "%s%s", (NR > 1 ? "," : ""), $4}' 2>/dev/null
}

get_ipv6() {
    local iface="$1"
    run_cmd ip -o -6 addr show dev "$iface" 2>/dev/null |
        run_cmd awk '{printf "%s%s", (NR > 1 ? "," : ""), $4}' 2>/dev/null
}

get_permanent_mac() {
    local iface="$1"
    local permanent_mac

    if ! "$ETHTOOL_AVAILABLE"; then
        echo "-"
        return
    fi

    permanent_mac="$(
        run_cmd ethtool -P "$iface" 2>/dev/null |
            run_cmd awk '
                /Permanent address:/ {
                    if (split($3, parts, ":") == 6)
                        print $3
                }
            ' 2>/dev/null
    )"

    if [ -z "$permanent_mac" ]; then
        echo "-"
    else
        echo "$permanent_mac"
    fi
}

print_interface() {
    local iface="$1"
    local num="$2"
    local current_mac="-"
    local permanent_mac="-"
    local state="-"
    local match="-"
    local ipv4="-"
    local ipv6="-"

    if [ -r "/sys/class/net/$iface/address" ]; then
        read -r current_mac < "/sys/class/net/$iface/address"
    fi

    if [ -r "/sys/class/net/$iface/operstate" ]; then
        read -r state < "/sys/class/net/$iface/operstate"
    fi

    permanent_mac="$(get_permanent_mac "$iface")"

    if [ "$permanent_mac" != "-" ]; then
        if [ "$current_mac" = "$permanent_mac" ]; then
            match="YES"
        else
            match="NO"
        fi
    fi

    ipv4="$(get_ipv4 "$iface")"
    ipv6="$(get_ipv6 "$iface")"

    [ -z "$ipv4" ] && ipv4="-"
    [ -z "$ipv6" ] && ipv6="-"

    printf "%-4s %-20s %-10s %-20s %-20s %-8s %-80s %-50s\n" \
        "$num" "$iface" "$state" "$current_mac" "$permanent_mac" "$match" "$ipv4" "$ipv6"
}

print_physical_interfaces() {
    local count=1
    local found=0
    local path
    local iface

    echo
    echo "PHYSICAL INTERFACES"
    echo
    print_header

    while IFS= read -r path; do
        iface="${path##*/}"

        if ! interface_matches_filter "$iface"; then
            continue
        fi

        if [ -e "$path/device" ]; then
            print_interface "$iface" "$count"
            count=$((count + 1))
            found=1
        fi
    done < <(printf '%s\n' /sys/class/net/* | natural_sort)

    [ "$found" -eq 0 ] && echo "No matching physical interfaces found."
}

print_virtual_interfaces() {
    local count=1
    local found=0
    local path
    local iface

    echo
    echo "VIRTUAL / LOGICAL INTERFACES"
    echo
    print_header

    while IFS= read -r path; do
        iface="${path##*/}"
        [ "$iface" = "lo" ] && continue

        if ! interface_matches_filter "$iface"; then
            continue
        fi

        if [ ! -e "$path/device" ]; then
            print_interface "$iface" "$count"
            count=$((count + 1))
            found=1
        fi
    done < <(printf '%s\n' /sys/class/net/* | natural_sort)

    [ "$found" -eq 0 ] && echo "No matching virtual/logical interfaces found."
}

print_title
print_physical_interfaces
print_virtual_interfaces

echo
printf '%s\n' "$SEPARATOR"
