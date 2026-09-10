#!/usr/bin/env bash

BUSYBOX_BIN=""
BUSYBOX_APPLETS=""

if command -v busybox >/dev/null 2>&1; then
    BUSYBOX_BIN="$(command -v busybox 2>/dev/null)"
    BUSYBOX_APPLETS="$("$BUSYBOX_BIN" --list 2>/dev/null || true)"
fi

busybox_has() {
    local applet="$1"

    [ -n "$BUSYBOX_BIN" ] || return 1
    [ -n "$BUSYBOX_APPLETS" ] || return 1

    case "
$BUSYBOX_APPLETS
" in
        *"
$applet
"*) return 0 ;;
        *) return 1 ;;
    esac
}

command_source() {
    local cmd="$1"
    local path=""

    if command -v "$cmd" >/dev/null 2>&1; then
        path="$(command -v "$cmd" 2>/dev/null)"
        printf 'native:%s' "$path"
        return 0
    fi

    if busybox_has "$cmd"; then
        printf 'busybox:%s %s' "$BUSYBOX_BIN" "$cmd"
        return 0
    fi

    printf '%s' 'missing'
    return 1
}

get_hostname() {
    local value=""

    if command -v hostname >/dev/null 2>&1; then
        value="$(hostname 2>/dev/null || true)"
    elif busybox_has hostname; then
        value="$("$BUSYBOX_BIN" hostname 2>/dev/null || true)"
    fi

    if [ -z "$value" ] && [ -r /proc/sys/kernel/hostname ]; then
        read -r value < /proc/sys/kernel/hostname || value=""
    fi

    [ -z "$value" ] && value="UNKNOWN"
    printf '%s' "$value"
}

get_timestamp() {
    local value=""

    if command -v date >/dev/null 2>&1; then
        value="$(date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || true)"
    elif busybox_has date; then
        value="$("$BUSYBOX_BIN" date '+%Y-%m-%d %H:%M:%S %Z' 2>/dev/null || true)"
    fi

    [ -z "$value" ] && value="UNKNOWN"
    printf '%s' "$value"
}

HOST="$(get_hostname)"
TIMESTAMP="$(get_timestamp)"

printf 'HOST:      %s\n' "$HOST"
printf 'TIMESTAMP: %s\n\n' "$TIMESTAMP"

if [ -n "$BUSYBOX_BIN" ]; then
    BUSYBOX_VERSION="$("$BUSYBOX_BIN" 2>&1 | { IFS= read -r line; printf '%s' "$line"; })"
    printf 'BUSYBOX:   %s\n' "$BUSYBOX_BIN"
    printf 'VERSION:   %s\n' "$BUSYBOX_VERSION"
else
    echo 'BUSYBOX:   not found'
fi

printf '\n%-16s %-12s %s\n' "COMMAND" "STATUS" "SOURCE"
printf '%s\n' '----------------------------------------------------------------------------'

COMMANDS=(
    hostname date awk sed grep sort tr cat
    ip route ifconfig arp
    ping traceroute nslookup
    netstat ss
    ethtool
    uname uptime free df dmesg tail head cut readlink
)

for cmd in "${COMMANDS[@]}"; do
    source_value="$(command_source "$cmd" 2>/dev/null || true)"

    case "$source_value" in
        native:*) status="NATIVE" ;;
        busybox:*) status="BUSYBOX" ;;
        *) status="MISSING" ;;
    esac

    printf '%-16s %-12s %s\n' "$cmd" "$status" "$source_value"
done

printf '\n=== NETWORK-RELATED BUSYBOX APPLETS ===\n'
if [ -n "$BUSYBOX_BIN" ]; then
    found=0
    for cmd in ip route ifconfig arp ping traceroute nslookup netstat hostname; do
        if busybox_has "$cmd"; then
            printf '%s\n' "$cmd"
            found=1
        fi
    done
    [ "$found" -eq 0 ] && echo 'No selected network applets detected.'
else
    echo 'BusyBox is not available.'
fi
