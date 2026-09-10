#!/usr/bin/env bash

HOST="$(hostname)"
TIMESTAMP="$(date '+%Y-%m-%d %H:%M:%S %Z')"

printf 'HOST:      %s\n' "$HOST"
printf 'TIMESTAMP: %s\n\n' "$TIMESTAMP"

echo '=== KERNEL ==='
uname -a 2>/dev/null || true

echo

echo '=== UPTIME ==='
uptime 2>/dev/null || true

echo

echo '=== CPU ==='
if [ -r /proc/cpuinfo ]; then
    awk -F: '
        /^model name/ && !seen_model {gsub(/^[ \t]+/, "", $2); print "Model: " $2; seen_model=1}
        /^processor/ {count++}
        END {if (count > 0) print "Logical CPUs: " count}
    ' /proc/cpuinfo
fi

echo

echo '=== MEMORY ==='
if command -v free >/dev/null 2>&1; then
    free -h 2>/dev/null || free 2>/dev/null || true
elif [ -r /proc/meminfo ]; then
    awk '/^(MemTotal|MemFree|MemAvailable|Buffers|Cached):/ {print}' /proc/meminfo
fi

echo

echo '=== FILESYSTEMS ==='
df -h 2>/dev/null || df 2>/dev/null || true
