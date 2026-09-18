#!/usr/bin/env bash

# Forcepoint SMC can invoke post-task scripts explicitly through /bin/sh,
# which ignores this shebang. Keep this bootstrap POSIX-compatible so an
# sh-started process can immediately re-exec the script under Bash.
if [ -z "${BASH_VERSION:-}" ]; then
    if command -v bash >/dev/null 2>&1; then
        exec bash "$0" "$@"
    fi

    echo "ERROR: bash is required to run forcepoint-backup-cleanup.sh." >&2
    exit 1
fi

set -Eeuo pipefail

if (( BASH_VERSINFO[0] < 3 )); then
    echo "ERROR: Bash 3 or newer is required." >&2
    exit 1
fi

# Forcepoint SMC backup retention cleanup.
#
# Intended for the SMC "Script to Execute After the Task" hook.
#
# Management Server backups (sgm) and Log Server backups (sgl) are stored in
# different locations and are therefore discovered independently:
#
#   SGConfiguration.txt          -> SG_BACKUP_DIR
#   LogServerConfiguration.txt   -> LOG_BACKUP_DIR
#
# Retention is evaluated independently for SGM and SGL backups.
# Manual/commented SGM backups are deleted only after at least KEEP_DATES
# automatic SGM dates exist, and only when they are older than the oldest
# retained automatic SGM date.

SCRIPT_NAME="${0##*/}"
DEFAULT_SMC_ROOT="/usr/local/forcepoint/smc"
SMC_ROOT="${FORCEPOINT_SMC_ROOT:-$DEFAULT_SMC_ROOT}"

MGT_CONFIG_OVERRIDE=""
LOG_CONFIG_OVERRIDE=""

KEEP_SGM_DATES=5
KEEP_SGL_DATES=5
MAX_DELETE_COUNT=500
STABLE_AGE_SECONDS=30
STABILITY_TIMEOUT_SECONDS=180
POLL_SECONDS=5

LOG_TAG="forcepoint-backup-cleanup"
LOG_FILE=""
LOCK_METHOD="auto"
LOCK_FILE=""
LOCK_DIR=""
LOCK_ACTIVE=""

DRY_RUN=false
SKIP_WAIT=false
RUN_ID="startup-$"

MGT_CONFIG_FILE=""
LOG_CONFIG_FILE=""
MGT_ENABLED=false
LOG_ENABLED=false
MGT_BACKUP_DIR=""
LOG_BACKUP_DIR=""
MGT_BACKUP_DIR_DEFAULTED=false
LOG_BACKUP_DIR_DEFAULTED=false

usage()
{
    cat <<'EOF'
Usage: forcepoint-backup-cleanup.sh [options]

Options:
  --dry-run                         Show the plan without deleting anything.
  --no-wait                         Skip the quiet-period wait. Intended for testing.
  --smc-root PATH                   SMC root. Default: /usr/local/forcepoint/smc
  --management-config FILE          Override SGConfiguration.txt path.
  --log-config FILE                 Override LogServerConfiguration.txt path.
  --keep-dates N                    Set both SGM and SGL retained distinct dates.
  --keep-sgm-dates N                Retained distinct Management Server dates.
  --keep-sgl-dates N                Retained distinct Log Server dates.
  --max-delete-count N              Refuse a run planning more than N deletions.
                                     0 disables this threshold. Default: 500.
  --stable-age-seconds N            Quiet age required for newest backup entry.
                                     Default: 30.
  --stability-timeout-seconds N     Maximum wait for the quiet condition.
                                     Default: 180.
  --poll-seconds N                  Quiet-condition polling interval. Default: 5.
  --lock-method auto|flock|mkdir    Lock implementation. Default: auto.
  --log-file FILE                   Also append script logs to FILE.
  --help                            Show this help text.

Environment:
  FORCEPOINT_SMC_ROOT               Alternative default for --smc-root.

Normal execution is destructive. Use --dry-run before enabling scheduled use.
EOF
}

log()
{
    local level="$1"
    shift
    local message="$*"
    local line

    line="$(date '+%Y-%m-%d %H:%M:%S') - run_id=$RUN_ID level=$level - $message"
    printf '%s\n' "$line"

    if command -v logger >/dev/null 2>&1; then
        logger -t "$LOG_TAG" "$line" 2>/dev/null || true
    fi

    if [[ -n "$LOG_FILE" ]]; then
        printf '%s\n' "$line" >> "$LOG_FILE" 2>/dev/null || true
    fi
}

die()
{
    log ERROR "$*"
    exit 1
}

cleanup_lock()
{
    if [[ "$LOCK_ACTIVE" == "mkdir" && -n "$LOCK_DIR" && -d "$LOCK_DIR" ]]; then
        rm -f -- "$LOCK_DIR/pid" 2>/dev/null || true
        rmdir -- "$LOCK_DIR" 2>/dev/null || true
    fi
}

on_error()
{
    local status="$1"
    local line="$2"
    local command="$3"

    trap - ERR
    log ERROR "unexpected_failure exit_code=$status line=$line command=$command"
    exit "$status"
}

trap cleanup_lock EXIT
trap 'on_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

trim_value()
{
    local value="$1"

    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"

    case "$value" in
        \"*\")
            value="${value#\"}"
            value="${value%\"}"
            ;;
        \'*\')
            value="${value#\'}"
            value="${value%\'}"
            ;;
    esac

    printf '%s\n' "$value"
}

read_config_value()
{
    local file="$1"
    local key="$2"
    local line
    local value=""

    [[ -r "$file" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"

        if [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*=(.*)$ ]]; then
            value="$(trim_value "${BASH_REMATCH[1]}")"
        fi
    done < "$file"

    [[ -n "$value" ]] || return 1
    printf '%s\n' "$value"
}

config_key_exists()
{
    local file="$1"
    local key="$2"
    local line

    [[ -r "$file" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        if [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*= ]]; then
            return 0
        fi
    done < "$file"

    return 1
}

resolve_backup_dir()
{
    local file="$1"
    local key="$2"
    local raw
    local data_root_token='${SG_DATA_ROOT_DIR}'

    raw="$(read_config_value "$file" "$key")" || return 1

    raw="${raw//$data_root_token/$SMC_DATA_ROOT_DIR}"

    [[ "$raw" != *'${'* ]] || return 2
    [[ "$raw" == /* ]] || return 3
    [[ "$raw" != "/" ]] || return 4

    if [[ "$raw" != "/" ]]; then
        raw="${raw%/}"
    fi

    printf '%s\n' "$raw"
}

validate_backup_dir()
{
    local label="$1"
    local path="$2"

    [[ -d "$path" ]] ||
        die "$label backup directory does not exist: $path"

    [[ -r "$path" ]] ||
        die "$label backup directory is not readable: $path"

    [[ -x "$path" ]] ||
        die "$label backup directory is not traversable: $path"

    if [[ "$DRY_RUN" != true ]]; then
        [[ -w "$path" ]] ||
            die "$label backup directory is not writable: $path"
    fi
}

get_sgl_automatic_date()
{
    local path="$1"
    local name="${path##*/}"

    # Supported examples:
    # sgl_v7.4.1.12025_20260915_070000_no_logs_zip
    # sgl_v7.3.1.11715_20260201_230000_Backup giornaliero no Log Files_no_logs_zip
    if [[ -d "$path" &&
          "$name" =~ ^sgl_.*_([0-9]{8})_[0-9]{6}(_.*)?_no_logs_zip$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

get_sgm_automatic_date()
{
    local path="$1"
    local name="${path##*/}"

    if [[ -f "$path" &&
          "$name" =~ ^sgm_.*_([0-9]{8})_[0-9]{6}\.zip$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

get_sgm_manual_date()
{
    local path="$1"
    local name="${path##*/}"

    if [[ -f "$path" &&
          "$name" =~ ^sgm_.*_([0-9]{8})_[0-9]{6}_.+\.zip$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

delete_directory()
{
    local label="$1"
    local path="$2"

    if [[ "$DRY_RUN" == true ]]; then
        log "WOULD DELETE $label: $path"
        return 0
    fi

    if rm -rf -- "$path"; then
        log "DELETE $label: $path"
        return 0
    fi

    log "ERROR: Failed to delete $label: $path"
    return 1
}

delete_file()
{
    local label="$1"
    local path="$2"

    if [[ "$DRY_RUN" == true ]]; then
        log "WOULD DELETE $label: $path"
        return 0
    fi

    if rm -f -- "$path"; then
        log "DELETE $label: $path"
        return 0
    fi

    log "ERROR: Failed to delete $label: $path"
    return 1
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run)
            DRY_RUN=true
            ;;
        --no-wait)
            SKIP_WAIT=true
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            usage >&2
            die "Unknown argument: $1"
            ;;
    esac
    shift
done

[[ -r "$MGT_CONFIG_FILE" ]] ||
    die "Management Server configuration file is not readable: $MGT_CONFIG_FILE"

[[ -r "$LOG_CONFIG_FILE" ]] ||
    die "Log Server configuration file is not readable: $LOG_CONFIG_FILE"

SMC_DATA_ROOT_DIR="$(cd -- "$(dirname -- "$MGT_CONFIG_FILE")/.." && pwd -P)" ||
    die "Could not determine SG_DATA_ROOT_DIR"

DEFAULT_BACKUP_DIR="${SMC_DATA_ROOT_DIR}/backups"
MGT_BACKUP_DIR_DEFAULTED=false

if config_key_exists "$MGT_CONFIG_FILE" "SG_BACKUP_DIR"; then
    MGT_BACKUP_DIR="$(resolve_backup_dir "$MGT_CONFIG_FILE" "SG_BACKUP_DIR")" ||
        die "Could not safely resolve SG_BACKUP_DIR from $MGT_CONFIG_FILE"
else
    MGT_BACKUP_DIR="$DEFAULT_BACKUP_DIR"
    MGT_BACKUP_DIR_DEFAULTED=true
fi

LOG_BACKUP_DIR="$(resolve_backup_dir "$LOG_CONFIG_FILE" "LOG_BACKUP_DIR")" ||
    die "Could not safely resolve LOG_BACKUP_DIR from $LOG_CONFIG_FILE"

validate_backup_dir "Management Server" "$MGT_BACKUP_DIR"
validate_backup_dir "Log Server" "$LOG_BACKUP_DIR"

command -v flock >/dev/null 2>&1 ||
    die "flock is required but was not found"

exec 9>"$LOCK_FILE"

if ! flock -n 9; then
    log "Another cleanup instance is already running. Exiting."
    exit 0
fi

if [[ "$MGT_BACKUP_DIR_DEFAULTED" == true ]]; then
    log "SG_BACKUP_DIR not found in $MGT_CONFIG_FILE; using default SGM backup directory: $MGT_BACKUP_DIR"
else
    log "Using SGM backup directory from $MGT_CONFIG_FILE: $MGT_BACKUP_DIR"
fi

log "Using SGL backup directory from $LOG_CONFIG_FILE: $LOG_BACKUP_DIR"

if [[ "$DRY_RUN" == true ]]; then
    log "DRY RUN enabled. No files or directories will be deleted."
fi

if [[ "$SKIP_WAIT" != true && $WAIT_SECONDS -gt 0 ]]; then
    log "Waiting $WAIT_SECONDS seconds before evaluating retention."
    sleep "$WAIT_SECONDS"
fi

shopt -s nullglob

declare -A sgl_dates=()
declare -A sgm_dates=()

for path in "$LOG_BACKUP_DIR"/*; do
    if backup_date="$(get_sgl_automatic_date "$path")"; then
        sgl_dates["$backup_date"]=1
    fi
done

for path in "$MGT_BACKUP_DIR"/*; do
    if backup_date="$(get_sgm_automatic_date "$path")"; then
        sgm_dates["$backup_date"]=1
    fi
done

if [[ ${#sgl_dates[@]} -eq 0 && ${#sgm_dates[@]} -eq 0 ]]; then
    log "No recognized automatic Forcepoint backups found. Nothing deleted."
    exit 0
fi

sorted_sgl_dates=()
sorted_sgm_dates=()
keep_sgl_dates=()
keep_sgm_dates=()

if [[ ${#sgl_dates[@]} -gt 0 ]]; then
    mapfile -t sorted_sgl_dates < <(
        printf '%s\n' "${!sgl_dates[@]}" | sort -r
    )
    keep_sgl_dates=("${sorted_sgl_dates[@]:0:$KEEP_DATES}")
fi

if [[ ${#sgm_dates[@]} -gt 0 ]]; then
    mapfile -t sorted_sgm_dates < <(
        printf '%s\n' "${!sgm_dates[@]}" | sort -r
    )
    keep_sgm_dates=("${sorted_sgm_dates[@]:0:$KEEP_DATES}")
fi

declare -A keep_sgl=()
declare -A keep_sgm=()

for backup_date in "${keep_sgl_dates[@]}"; do
    keep_sgl["$backup_date"]=1
done

for backup_date in "${keep_sgm_dates[@]}"; do
    keep_sgm["$backup_date"]=1
done

if [[ ${#keep_sgl_dates[@]} -gt 0 ]]; then
    log "Keeping SGL automatic backup dates: ${keep_sgl_dates[*]}"
else
    log "No recognized SGL automatic backups found in $LOG_BACKUP_DIR"
fi

if [[ ${#keep_sgm_dates[@]} -gt 0 ]]; then
    log "Keeping SGM automatic backup dates: ${keep_sgm_dates[*]}"
else
    log "No recognized SGM automatic backups found in $MGT_BACKUP_DIR"
fi

manual_cleanup_enabled=false
manual_cutoff=""

if [[ ${#sgm_dates[@]} -ge $KEEP_DATES ]]; then
    manual_cleanup_enabled=true
    manual_cutoff="${keep_sgm_dates[$((${#keep_sgm_dates[@]} - 1))]}"
    log "Manual/commented SGM backups older than $manual_cutoff are eligible for deletion."
else
    log "Manual/commented SGM cleanup skipped: only ${#sgm_dates[@]} distinct automatic SGM backup date(s) exist; $KEEP_DATES are required."
fi

sgl_kept=0
sgl_selected=0
sgm_kept=0
sgm_selected=0
manual_kept=0
manual_selected=0
errors=0

for path in "$LOG_BACKUP_DIR"/*; do
    if ! backup_date="$(get_sgl_automatic_date "$path")"; then
        continue
    fi

    if [[ -n "${keep_sgl[$backup_date]+x}" ]]; then
        log "KEEP SGL AUTOMATIC: $path"
        ((sgl_kept += 1))
        continue
    fi

    if delete_directory "SGL AUTOMATIC" "$path"; then
        ((sgl_selected += 1))
    else
        ((errors += 1))
    fi
done

for path in "$MGT_BACKUP_DIR"/*; do
    if ! backup_date="$(get_sgm_automatic_date "$path")"; then
        continue
    fi

    if [[ -n "${keep_sgm[$backup_date]+x}" ]]; then
        log "KEEP SGM AUTOMATIC: $path"
        ((sgm_kept += 1))
        continue
    fi

    if delete_file "SGM AUTOMATIC" "$path"; then
        ((sgm_selected += 1))
    else
        ((errors += 1))
    fi
done

if [[ "$manual_cleanup_enabled" == true ]]; then
    for path in "$MGT_BACKUP_DIR"/*; do
        if ! backup_date="$(get_sgm_manual_date "$path")"; then
            continue
        fi

        if [[ "$backup_date" < "$manual_cutoff" ]]; then
            if delete_file "SGM MANUAL/COMMENTED" "$path"; then
                ((manual_selected += 1))
            else
                ((errors += 1))
            fi
        else
            log "KEEP SGM MANUAL/COMMENTED: $path"
            ((manual_kept += 1))
        fi
    done
fi

if [[ "$DRY_RUN" == true ]]; then
    log "DRY RUN complete. SGL automatic: kept=$sgl_kept would_delete=$sgl_selected"
    log "DRY RUN complete. SGM automatic: kept=$sgm_kept would_delete=$sgm_selected"
    log "DRY RUN complete. SGM manual/commented: kept=$manual_kept would_delete=$manual_selected"
else
    log "Cleanup completed. SGL automatic: kept=$sgl_kept deleted=$sgl_selected"
    log "Cleanup completed. SGM automatic: kept=$sgm_kept deleted=$sgm_selected"
    log "Cleanup completed. SGM manual/commented: kept=$manual_kept deleted=$manual_selected"
fi

if [[ $errors -gt 0 ]]; then
    log "ERROR: Cleanup completed with $errors deletion error(s)."
    exit 1
fi

exit 0
