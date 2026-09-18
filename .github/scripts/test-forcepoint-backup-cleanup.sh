#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT_DIR/maintenance/forcepoint-backup-cleanup.sh"
TMP_ROOT="$(mktemp -d)"
trap 'rm -rf -- "$TMP_ROOT"' EXIT

fail()
{
    echo "TEST FAILURE: $*" >&2
    exit 1
}

assert_contains()
{
    local haystack="$1"
    local needle="$2"

    grep -F -- "$needle" <<<"$haystack" >/dev/null ||
        fail "expected output to contain: $needle"
}

make_sgm()
{
    local dir="$1"
    local date="$2"
    local time="${3:-120000}"
    : > "$dir/sgm_v7.4.1.12025_${date}_${time}.zip"
}

make_sgm_manual()
{
    local dir="$1"
    local date="$2"
    local time="${3:-120000}"
    : > "$dir/sgm_v7.4.1.12025_${date}_${time}_Manual test backup.zip"
}

make_sgl()
{
    local dir="$1"
    local date="$2"
    local time="${3:-230000}"
    mkdir -p -- "$dir/sgl_v7.4.1.12025_${date}_${time}_Backup test_no_logs_zip"
}

echo "Test: sh bootstrap"
sh "$SCRIPT" --help >/dev/null

echo "Test: Management-only discovery, retention and manual cutoff"
case1="$TMP_ROOT/case1"
mkdir -p "$case1/smc/data" "$case1/sgm"
cat > "$case1/smc/data/SGConfiguration.txt" <<EOF
SG_BACKUP_DIR=$case1/sgm
EOF
for date in 20260912 20260913 20260914 20260915 20260916 20260917 20260918; do
    make_sgm "$case1/sgm" "$date"
done
make_sgm "$case1/sgm" 20260918 130000
make_sgm_manual "$case1/sgm" 20260913 090000
make_sgm_manual "$case1/sgm" 20260917 090000

output="$("$SCRIPT" --smc-root "$case1/smc" --dry-run --no-wait --lock-method mkdir)"
assert_contains "$output" "source=SGL disabled reason=configuration_not_found_or_unreadable"
assert_contains "$output" "WOULD DELETE SGM AUTOMATIC: $case1/sgm/sgm_v7.4.1.12025_20260912_120000.zip"
assert_contains "$output" "WOULD DELETE SGM AUTOMATIC: $case1/sgm/sgm_v7.4.1.12025_20260913_120000.zip"
assert_contains "$output" "WOULD DELETE SGM MANUAL/COMMENTED: $case1/sgm/sgm_v7.4.1.12025_20260913_090000_Manual test backup.zip"
assert_contains "$output" "KEEP SGM MANUAL/COMMENTED: $case1/sgm/sgm_v7.4.1.12025_20260917_090000_Manual test backup.zip"
assert_contains "$output" "DRY RUN complete. SGM automatic: kept=6 would_delete=2"

echo "Test: SG_BACKUP_DIR default fallback"
case2="$TMP_ROOT/case2"
mkdir -p "$case2/smc/data" "$case2/smc/backups"
printf '%s\n' '# no SG_BACKUP_DIR on this installation' > "$case2/smc/data/SGConfiguration.txt"
for date in 20260914 20260915 20260916 20260917 20260918; do
    make_sgm "$case2/smc/backups" "$date"
done
output="$("$SCRIPT" --smc-root "$case2/smc" --dry-run --no-wait --lock-method mkdir)"
assert_contains "$output" "source=SGM path=$case2/smc/backups path_source=default reason=SG_BACKUP_DIR_missing"

echo "Test: Log-only discovery and SG_DATA_ROOT_DIR expansion"
case3="$TMP_ROOT/case3"
mkdir -p "$case3/smc/data" "$case3/smc/backups"
cat > "$case3/smc/data/LogServerConfiguration.txt" <<'EOF'
LOG_BACKUP_DIR=${SG_DATA_ROOT_DIR}/backups
EOF
for date in 20260913 20260914 20260915 20260916 20260917 20260918; do
    make_sgl "$case3/smc/backups" "$date"
done
output="$("$SCRIPT" --smc-root "$case3/smc" --dry-run --no-wait --lock-method mkdir)"
assert_contains "$output" "source=SGM disabled reason=configuration_not_found_or_unreadable"
assert_contains "$output" "source=SGL path=$case3/smc/backups path_source=config"
assert_contains "$output" "DRY RUN complete. SGL automatic: kept=5 would_delete=1"

echo "Test: identical SGM/SGL backup directory"
case4="$TMP_ROOT/case4"
mkdir -p "$case4/smc/data" "$case4/smc/backups"
cat > "$case4/smc/data/SGConfiguration.txt" <<EOF
SG_BACKUP_DIR=$case4/smc/backups
EOF
cat > "$case4/smc/data/LogServerConfiguration.txt" <<'EOF'
LOG_BACKUP_DIR=${SG_DATA_ROOT_DIR}/backups
EOF
for date in 20260914 20260915 20260916 20260917 20260918; do
    make_sgm "$case4/smc/backups" "$date"
    make_sgl "$case4/smc/backups" "$date"
done
output="$("$SCRIPT" --smc-root "$case4/smc" --dry-run --no-wait --lock-method mkdir)"
assert_contains "$output" "SGM and SGL backup directories are identical: $case4/smc/backups"

echo "Test: configurable retention"
output="$("$SCRIPT" --smc-root "$case1/smc" --dry-run --no-wait --lock-method mkdir --keep-sgm-dates 3)"
assert_contains "$output" "DRY RUN complete. SGM automatic: kept=4 would_delete=4"

echo "Test: deletion safety threshold"
if "$SCRIPT" --smc-root "$case1/smc" --dry-run --no-wait --lock-method mkdir --max-delete-count 1 >/tmp/forcepoint-cleanup-test.out 2>&1; then
    fail "expected max-delete-count safety check to fail"
fi
grep -F "Safety limit exceeded" /tmp/forcepoint-cleanup-test.out >/dev/null ||
    fail "max-delete-count failure message missing"
rm -f /tmp/forcepoint-cleanup-test.out

echo "Test: optional log file and run id"
log_file="$TMP_ROOT/cleanup.log"
"$SCRIPT" --smc-root "$case2/smc" --dry-run --no-wait --lock-method mkdir --log-file "$log_file" >/dev/null
grep -E 'run_id=[0-9]{8}T[0-9]{6}-[0-9]+' "$log_file" >/dev/null ||
    fail "structured run id missing from log file"

echo "All forcepoint-backup-cleanup tests passed."
