#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd -- "$SCRIPT_DIR/.." && pwd)"
DIST_DIR="$ROOT_DIR/dist"
CHECK_ONLY=false

if [ "${1:-}" = "--check" ]; then
    CHECK_ONLY=true
elif [ "$#" -gt 0 ]; then
    echo "Usage: $0 [--check]" >&2
    exit 2
fi

SOURCES=(
    "scripts/network/check-routing-path.sh"
    "scripts/network/get-bonds.sh"
    "scripts/network/get-interface-counters.sh"
    "scripts/network/get-interface-details.sh"
    "scripts/network/get-macs.sh"
    "scripts/network/get-neighbors.sh"
    "scripts/network/get-routes.sh"
    "scripts/network/get-vlans.sh"
    "scripts/vpn/collect-vpn-diagnostics.sh"
    "scripts/vpn/get-vpn-interfaces.sh"
    "scripts/vpn/get-vpn-routes.sh"
    "scripts/system/check-runtime.sh"
    "scripts/system/get-listening-sockets.sh"
    "scripts/system/get-system-info.sh"
    "scripts/troubleshooting/collect-network-diagnostics.sh"
)

mkdir -p "$DIST_DIR"
failed=0

for relative_src in "${SOURCES[@]}"; do
    src="$ROOT_DIR/$relative_src"
    dest="$DIST_DIR/${relative_src##*/}"

    if [ ! -f "$src" ]; then
        echo "Missing source: $relative_src" >&2
        failed=1
        continue
    fi

    if "$CHECK_ONLY"; then
        if [ ! -f "$dest" ]; then
            echo "Missing dist file: ${dest#$ROOT_DIR/}" >&2
            failed=1
            continue
        fi

        if ! cmp -s "$src" "$dest"; then
            echo "Out of sync: ${dest#$ROOT_DIR/}" >&2
            failed=1
        fi

        if [ ! -x "$dest" ]; then
            echo "Not executable: ${dest#$ROOT_DIR/}" >&2
            failed=1
        fi
    else
        cp "$src" "$dest"
        chmod +x "$dest"
        echo "Updated ${dest#$ROOT_DIR/}"
    fi
done

if [ "$failed" -ne 0 ]; then
    exit 1
fi

if "$CHECK_ONLY"; then
    echo "dist/ is synchronized with the source manifest."
fi
