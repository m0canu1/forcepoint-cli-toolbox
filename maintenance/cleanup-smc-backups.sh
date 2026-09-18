#!/usr/bin/env bash

set -euo pipefail

# Forcepoint SMC backup retention cleanup.
#
# This script is intended for the SMC "Script to Execute After the Task"
# hook. It reads the configured backup directory from SGConfiguration.txt
# instead of hard-coding a path.
#
# Retention is evaluated independently for Log Server (sgl) and Management
# Server (sgm) automatic backups. Manual/commented SGM backups are deleted
# only after at least KEEP_DATES automatic SGM dates exist, and only when
# they are older than the oldest retained automatic SGM date.

CONFIG_FILE="/usr/local/forcepoint/smc/data/SGConfiguration.txt"
KEEP_DATES=5
WAIT_SECONDS=60
LOG_TAG="forcepoint-backup-cleanup"
LOCK_FILE="/tmp/forcepoint-backup-cleanup-${UID}.lock"

DRY_RUN=false
SKIP_WAIT=false

usage()
{
    cat <<'EOF'
Usage: cleanup-smc-backups.sh [--dry-run] [--no-wait] [--help]

Options:
  --dry-run   Show what would be deleted without deleting anything.
  --no-wait   Skip the normal post-task delay. Useful for manual testing.
  --help      Show this help text.

Default behavior is destructive: recognized backups outside the retention
window are deleted.
EOF
}

log()
{
    local message="$*"

    if command -v logger >/dev/null 2>&1; then
        logger -t "$LOG_TAG" "$message" 2>/dev/null || true
    fi

    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message"
}

die()
{
    log "ERROR: $*"
    exit 1
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

read_backup_dir()
{
    local line
    local value=""

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"

        if [[ "$line" =~ ^[[:space:]]*SG_BACKUP_DIR[[:space:]]*=(.*)$ ]]; then
            value="${BASH_REMATCH[1]}"

            # Trim leading and trailing whitespace without evaluating the value.
            value="${value#"${value%%[![:space:]]*}"}"
            value="${value%"${value##*[![:space:]]}"}"

            # Accept a fully quoted path while still treating the configuration
            # as data rather than sourcing it as shell code.
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
        fi
    done < "$CONFIG_FILE"

    [[ -n "$value" ]] || return 1
    printf '%s\n' "$value"
}

get_sgl_automatic_date()
{
    local path="$1"
    local name="${path##*/}"

    if [[ -d "$path" &&
          "$name" =~ ^sgl_.*_([0-9]{8})_[0-9]{6}_no_logs_zip$ ]]; then
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

[[ -r "$CONFIG_FILE" ]] || die "Configuration file is not readable: $CONFIG_FILE"

BACKUP_DIR="$(read_backup_dir)" ||
    die "SG_BACKUP_DIR was not found or is empty in $CONFIG_FILE"

[[ "$BACKUP_DIR" != *'\${'* ]] ||
    die "SG_BACKUP_DIR contains an unresolved variable expression: $BACKUP_DIR"

[[ "$BACKUP_DIR" == /* ]] ||
    die "SG_BACKUP_DIR must be an absolute path: $BACKUP_DIR"

[[ "$BACKUP_DIR" != "/" ]] ||
    die "Refusing to use / as SG_BACKUP_DIR"

[[ -d "$BACKUP_DIR" ]] ||
    die "Configured backup directory does not exist: $BACKUP_DIR"

[[ -r "$BACKUP_DIR" ]] ||
    die "Configured backup directory is not readable: $BACKUP_DIR"

[[ -x "$BACKUP_DIR" ]] ||
    die "Configured backup directory is not traversable: $BACKUP_DIR"

if [[ "$DRY_RUN" != true ]]; then
    [[ -w "$BACKUP_DIR" ]] ||
        die "Configured backup directory is not writable: $BACKUP_DIR"
fi

command -v flock >/dev/null 2>&1 ||
    die "flock is required but was not found"

exec 9>"$LOCK_FILE"

if ! flock -n 9; then
    log "Another cleanup instance is already running. Exiting."
    exit 0
fi

log "Using SG_BACKUP_DIR from $CONFIG_FILE: $BACKUP_DIR"

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

for path in "$BACKUP_DIR"/*; do
    if backup_date="$(get_sgl_automatic_date "$path")"; then
        sgl_dates["$backup_date"]=1
        continue
    fi

    if backup_date="$(get_sgm_automatic_date "$path")"; then
        sgm_dates["$backup_date"]=1
    fi
done

if [[ ${#sgl_dates[@]} -eq 0 && ${#sgm_dates[@]} -eq 0 ]]; then
    log "No recognized automatic Forcepoint backups found. Nothing deleted."
    exit 0
fi

keep_sgl_dates=()
keep_sgm_dates=()

if [[ ${#sgl_dates[@]} -gt 0 ]]; then
    mapfile -t keep_sgl_dates < <(
        printf '%s\n' "${!sgl_dates[@]}" |
            sort -r |
            head -n "$KEEP_DATES"
    )
fi

if [[ ${#sgm_dates[@]} -gt 0 ]]; then
    mapfile -t keep_sgm_dates < <(
        printf '%s\n' "${!sgm_dates[@]}" |
            sort -r |
            head -n "$KEEP_DATES"
    )
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
fi

if [[ ${#keep_sgm_dates[@]} -gt 0 ]]; then
    log "Keeping SGM automatic backup dates: ${keep_sgm_dates[*]}"
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

for path in "$BACKUP_DIR"/*; do
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

for path in "$BACKUP_DIR"/*; do
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
    for path in "$BACKUP_DIR"/*; do
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
