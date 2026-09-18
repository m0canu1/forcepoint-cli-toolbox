#!/usr/bin/env bash

set -euo pipefail

CONFIG_FILE="/usr/local/forcepoint/smc/data/SGConfiguration.txt"
KEEP_DATES=5
WAIT_SECONDS=60
LOG_TAG="forcepoint-smc-backup-cleanup"
DRY_RUN=false
SKIP_WAIT=false

usage() {
    cat <<'USAGE'
Usage: cleanup-smc-backups.sh [--dry-run] [--no-wait] [--help]

Cleans Forcepoint SMC backups using the backup directory configured in
/usr/local/forcepoint/smc/data/SGConfiguration.txt (SG_BACKUP_DIR).

Retention policy:
  - keep the 5 most recent distinct automatic backup dates;
  - delete older automatic Log Server and Management Server backups;
  - delete manual/commented Management Server backups only when their date is
    older than the oldest of the 5 retained automatic backup dates;
  - ignore unrecognized files and directories.

Options:
  --dry-run   Show what would be deleted without removing anything.
  --no-wait   Skip the default 60-second delay used for SMC post-task execution.
  --help      Show this help text.
USAGE
}

log() {
    local message="$*"
    printf '%s - %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$message"
    if command -v logger >/dev/null 2>&1; then
        logger -t "$LOG_TAG" -- "$message"
    fi
}

trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    printf '%s\n' "$value"
}

read_backup_dir() {
    local line value

    if [[ ! -r "$CONFIG_FILE" ]]; then
        log "ERROR: Cannot read Forcepoint SMC configuration file: $CONFIG_FILE"
        return 1
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"

        if [[ "$line" =~ ^[[:space:]]*SG_BACKUP_DIR[[:space:]]*=(.*)$ ]]; then
            value="$(trim_whitespace "${BASH_REMATCH[1]}")"

            case "$value" in
                \"*\") value="${value#\"}"; value="${value%\"}" ;;
                \'*\') value="${value#\'}"; value="${value%\'}" ;;
            esac

            if [[ -z "$value" ]]; then
                log "ERROR: SG_BACKUP_DIR is present but empty in $CONFIG_FILE"
                return 1
            fi

            if [[ "$value" != /* ]]; then
                log "ERROR: SG_BACKUP_DIR must be an absolute path: $value"
                return 1
            fi

            if [[ "$value" == "/" ]]; then
                log "ERROR: Refusing to use / as SG_BACKUP_DIR"
                return 1
            fi

            if [[ "$value" == *'${'* ]]; then
                log "ERROR: SG_BACKUP_DIR contains an unresolved variable expression: $value"
                return 1
            fi

            printf '%s\n' "$value"
            return 0
        fi
    done < "$CONFIG_FILE"

    log "ERROR: SG_BACKUP_DIR was not found in $CONFIG_FILE"
    return 1
}

get_automatic_backup_date() {
    local path="$1"
    local name="${path##*/}"

    if [[ -d "$path" && "$name" =~ ^sgl_.*_([0-9]{8})_[0-9]{6}_no_logs_zip$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    if [[ -f "$path" && "$name" =~ ^sgm_.*_([0-9]{8})_[0-9]{6}\.zip$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

get_manual_backup_date() {
    local path="$1"
    local name="${path##*/}"

    if [[ -f "$path" && "$name" =~ ^sgm_.*_([0-9]{8})_[0-9]{6}_.+\.zip$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

for arg in "$@"; do
    case "$arg" in
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
            printf 'Unknown option: %s\n\n' "$arg" >&2
            usage >&2
            exit 2
            ;;
    esac
done

if ! command -v flock >/dev/null 2>&1; then
    log "ERROR: flock command not found"
    exit 1
fi

BACKUP_DIR="$(read_backup_dir)"

if [[ ! -d "$BACKUP_DIR" ]]; then
    log "ERROR: Configured backup directory does not exist: $BACKUP_DIR"
    exit 1
fi

if [[ ! -r "$BACKUP_DIR" || ! -x "$BACKUP_DIR" ]]; then
    log "ERROR: Configured backup directory is not readable/traversable: $BACKUP_DIR"
    exit 1
fi

if [[ "$DRY_RUN" == false && ! -w "$BACKUP_DIR" ]]; then
    log "ERROR: Configured backup directory is not writable: $BACKUP_DIR"
    exit 1
fi

LOCK_FILE="/tmp/forcepoint-smc-backup-cleanup-${UID}.lock"
exec 9>"$LOCK_FILE"

if ! flock -n 9; then
    log "Another cleanup instance is already running for UID $UID. Exiting."
    exit 0
fi

if [[ "$SKIP_WAIT" == false ]]; then
    log "Cleanup triggered. Waiting ${WAIT_SECONDS} seconds before processing."
    sleep "$WAIT_SECONDS"
fi

shopt -s nullglob

declare -A available_dates

for path in "$BACKUP_DIR"/*; do
    if backup_date="$(get_automatic_backup_date "$path")"; then
        available_dates["$backup_date"]=1
    fi
done

if [[ ${#available_dates[@]} -eq 0 ]]; then
    log "No recognized automatic Forcepoint backups found. Nothing deleted."
    exit 0
fi

mapfile -t keep_dates < <(
    printf '%s\n' "${!available_dates[@]}" |
        sort -r |
        head -n "$KEEP_DATES"
)

if [[ ${#keep_dates[@]} -lt "$KEEP_DATES" ]]; then
    log "Only ${#keep_dates[@]} distinct automatic backup date(s) found; at least $KEEP_DATES are required before cleanup. Nothing deleted."
    exit 0
fi

declare -A keep
for backup_date in "${keep_dates[@]}"; do
    keep["$backup_date"]=1
done

cutoff_date="${keep_dates[$((${#keep_dates[@]} - 1))]}"

log "Backup directory: $BACKUP_DIR"
log "Keeping automatic backup dates: ${keep_dates[*]}"
log "Manual backup cutoff date: $cutoff_date"

if [[ "$DRY_RUN" == true ]]; then
    log "DRY RUN enabled. No files or directories will be removed."
fi

automatic_kept=0
automatic_selected=0
manual_kept=0
manual_selected=0
errors=0

for path in "$BACKUP_DIR"/*; do
    if ! backup_date="$(get_automatic_backup_date "$path")"; then
        continue
    fi

    if [[ -n "${keep[$backup_date]+x}" ]]; then
        log "KEEP AUTOMATIC: $path"
        ((automatic_kept+=1))
        continue
    fi

    if [[ "$DRY_RUN" == true ]]; then
        log "WOULD DELETE AUTOMATIC: $path"
        ((automatic_selected+=1))
        continue
    fi

    log "DELETE AUTOMATIC: $path"
    if rm -rf -- "$path"; then
        ((automatic_selected+=1))
    else
        log "ERROR: Failed to delete automatic backup: $path"
        ((errors+=1))
    fi
done

for path in "$BACKUP_DIR"/*; do
    if ! backup_date="$(get_manual_backup_date "$path")"; then
        continue
    fi

    if [[ "$backup_date" < "$cutoff_date" ]]; then
        if [[ "$DRY_RUN" == true ]]; then
            log "WOULD DELETE MANUAL: $path"
            ((manual_selected+=1))
            continue
        fi

        log "DELETE MANUAL: $path"
        if rm -f -- "$path"; then
            ((manual_selected+=1))
        else
            log "ERROR: Failed to delete manual backup: $path"
            ((errors+=1))
        fi
    else
        log "KEEP MANUAL: $path"
        ((manual_kept+=1))
    fi
done

if [[ "$DRY_RUN" == true ]]; then
    log "Dry run completed. Automatic: kept=$automatic_kept would_delete=$automatic_selected. Manual: kept=$manual_kept would_delete=$manual_selected."
else
    log "Cleanup completed. Automatic: kept=$automatic_kept deleted=$automatic_selected. Manual: kept=$manual_kept deleted=$manual_selected. Errors=$errors."
fi

if [[ "$errors" -ne 0 ]]; then
    exit 1
fi

exit 0
