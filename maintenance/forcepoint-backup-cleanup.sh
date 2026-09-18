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

property_exists()
{
    local file="$1"
    local key="$2"
    local line

    [[ -r "$file" ]] || return 1

    while IFS= read -r line || [[ -n "$line" ]]; do
        line="${line%$'\r'}"
        if [[ "$line" =~ ^[[:space:]]*${key}[[:space:]]*= ]]; then
            return 0
        fi
    done < "$file"

    return 1
}

read_property()
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

resolve_forcepoint_path()
{
    local raw="$1"
    local data_root_braced='${SG_DATA_ROOT_DIR}'
    local data_root_plain='$SG_DATA_ROOT_DIR'

    raw="${raw//$data_root_braced/$SMC_ROOT}"
    raw="${raw//$data_root_plain/$SMC_ROOT}"

    [[ "$raw" != *'$'* ]] || return 2
    [[ "$raw" == /* ]] || return 3
    [[ "$raw" != "/" ]] || return 4

    raw="${raw%/}"
    printf '%s\n' "$raw"
}

require_nonnegative_integer()
{
    local name="$1"
    local value="$2"

    [[ "$value" =~ ^[0-9]+$ ]] ||
        die "$name must be a non-negative integer: $value"
}

require_positive_integer()
{
    local name="$1"
    local value="$2"

    require_nonnegative_integer "$name" "$value"
    (( value > 0 )) ||
        die "$name must be greater than zero"
}

validate_source_dir()
{
    local label="$1"
    local path="$2"

    if [[ ! -d "$path" ]]; then
        log WARN "source=$label disabled reason=directory_missing path=$path"
        return 1
    fi

    if [[ ! -r "$path" || ! -x "$path" ]]; then
        log WARN "source=$label disabled reason=directory_not_readable_or_traversable path=$path"
        return 1
    fi

    if [[ "$DRY_RUN" != true && ! -w "$path" ]]; then
        log WARN "source=$label disabled reason=directory_not_writable path=$path"
        return 1
    fi

    return 0
}

get_sgl_automatic_date()
{
    local path="$1"
    local name="${path##*/}"

    if [[ -d "$path" && ! -L "$path" &&
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

    if [[ -f "$path" && ! -L "$path" &&
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

    if [[ -f "$path" && ! -L "$path" &&
          "$name" =~ ^sgm_.*_([0-9]{8})_[0-9]{6}_.+\.zip$ ]]; then
        printf '%s\n' "${BASH_REMATCH[1]}"
        return 0
    fi

    return 1
}

date_in_list()
{
    local needle="$1"
    shift
    local item

    for item in "$@"; do
        [[ "$needle" == "$item" ]] && return 0
    done

    return 1
}

sort_unique_dates_desc()
{
    SORT_RESULT=()
    local value

    (( $# > 0 )) || return 0

    while IFS= read -r value; do
        [[ -n "$value" ]] && SORT_RESULT+=("$value")
    done < <(printf '%s\n' "$@" | LC_ALL=C sort -ru)
}

build_keep_dates()
{
    local keep_count="$1"
    shift
    local i

    sort_unique_dates_desc "$@"
    SORTED_RESULT=("${SORT_RESULT[@]}")
    KEEP_RESULT=()

    for ((i = 0; i < ${#SORTED_RESULT[@]} && i < keep_count; i++)); do
        KEEP_RESULT+=("${SORTED_RESULT[$i]}")
    done
}

parse_args()
{
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --dry-run)
                DRY_RUN=true
                ;;
            --no-wait)
                SKIP_WAIT=true
                ;;
            --smc-root)
                [[ $# -ge 2 ]] || die "--smc-root requires a path"
                SMC_ROOT="$2"
                shift
                ;;
            --management-config)
                [[ $# -ge 2 ]] || die "--management-config requires a file"
                MGT_CONFIG_OVERRIDE="$2"
                shift
                ;;
            --log-config)
                [[ $# -ge 2 ]] || die "--log-config requires a file"
                LOG_CONFIG_OVERRIDE="$2"
                shift
                ;;
            --keep-dates)
                [[ $# -ge 2 ]] || die "--keep-dates requires a value"
                KEEP_SGM_DATES="$2"
                KEEP_SGL_DATES="$2"
                shift
                ;;
            --keep-sgm-dates)
                [[ $# -ge 2 ]] || die "--keep-sgm-dates requires a value"
                KEEP_SGM_DATES="$2"
                shift
                ;;
            --keep-sgl-dates)
                [[ $# -ge 2 ]] || die "--keep-sgl-dates requires a value"
                KEEP_SGL_DATES="$2"
                shift
                ;;
            --max-delete-count)
                [[ $# -ge 2 ]] || die "--max-delete-count requires a value"
                MAX_DELETE_COUNT="$2"
                shift
                ;;
            --stable-age-seconds)
                [[ $# -ge 2 ]] || die "--stable-age-seconds requires a value"
                STABLE_AGE_SECONDS="$2"
                shift
                ;;
            --stability-timeout-seconds)
                [[ $# -ge 2 ]] || die "--stability-timeout-seconds requires a value"
                STABILITY_TIMEOUT_SECONDS="$2"
                shift
                ;;
            --poll-seconds)
                [[ $# -ge 2 ]] || die "--poll-seconds requires a value"
                POLL_SECONDS="$2"
                shift
                ;;
            --lock-method)
                [[ $# -ge 2 ]] || die "--lock-method requires a value"
                LOCK_METHOD="$2"
                shift
                ;;
            --log-file)
                [[ $# -ge 2 ]] || die "--log-file requires a file"
                LOG_FILE="$2"
                shift
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
}

validate_options()
{
    require_positive_integer "--keep-sgm-dates" "$KEEP_SGM_DATES"
    require_positive_integer "--keep-sgl-dates" "$KEEP_SGL_DATES"
    require_nonnegative_integer "--max-delete-count" "$MAX_DELETE_COUNT"
    require_nonnegative_integer "--stable-age-seconds" "$STABLE_AGE_SECONDS"
    require_positive_integer "--stability-timeout-seconds" "$STABILITY_TIMEOUT_SECONDS"
    require_positive_integer "--poll-seconds" "$POLL_SECONDS"

    case "$LOCK_METHOD" in
        auto|flock|mkdir)
            ;;
        *)
            die "--lock-method must be auto, flock, or mkdir"
            ;;
    esac

    [[ "$SMC_ROOT" == /* ]] ||
        die "--smc-root must be an absolute path: $SMC_ROOT"

    [[ "$SMC_ROOT" != "/" ]] ||
        die "--smc-root cannot be /"

    [[ -d "$SMC_ROOT" ]] ||
        die "SMC root does not exist: $SMC_ROOT"

    SMC_ROOT="$(cd -- "$SMC_ROOT" && pwd -P)"

    if [[ -n "$MGT_CONFIG_OVERRIDE" ]]; then
        [[ "$MGT_CONFIG_OVERRIDE" == /* ]] ||
            die "--management-config must be an absolute path"
    fi

    if [[ -n "$LOG_CONFIG_OVERRIDE" ]]; then
        [[ "$LOG_CONFIG_OVERRIDE" == /* ]] ||
            die "--log-config must be an absolute path"
    fi

    if [[ -n "$LOG_FILE" ]]; then
        [[ "$LOG_FILE" == /* ]] ||
            die "--log-file must be an absolute path: $LOG_FILE"

        : >> "$LOG_FILE" 2>/dev/null ||
            die "Cannot write log file: $LOG_FILE"
    fi
}

check_runtime_dependencies()
{
    local command
    local missing=()

    for command in date sort stat id rm mkdir rmdir sleep; do
        command -v "$command" >/dev/null 2>&1 || missing+=("$command")
    done

    if (( ${#missing[@]} > 0 )); then
        die "Missing required command(s): ${missing[*]}"
    fi
}

discover_sources()
{
    local raw
    local resolved

    if [[ -n "$MGT_CONFIG_OVERRIDE" ]]; then
        MGT_CONFIG_FILE="$MGT_CONFIG_OVERRIDE"
    else
        MGT_CONFIG_FILE="$SMC_ROOT/data/SGConfiguration.txt"
    fi

    if [[ -n "$LOG_CONFIG_OVERRIDE" ]]; then
        LOG_CONFIG_FILE="$LOG_CONFIG_OVERRIDE"
    else
        LOG_CONFIG_FILE="$SMC_ROOT/data/LogServerConfiguration.txt"
    fi

    if [[ -r "$MGT_CONFIG_FILE" ]]; then
        if property_exists "$MGT_CONFIG_FILE" "SG_BACKUP_DIR"; then
            if raw="$(read_property "$MGT_CONFIG_FILE" "SG_BACKUP_DIR")" &&
               resolved="$(resolve_forcepoint_path "$raw")"; then
                MGT_BACKUP_DIR="$resolved"
            else
                log WARN "source=SGM disabled reason=invalid_SG_BACKUP_DIR config=$MGT_CONFIG_FILE"
            fi
        else
            MGT_BACKUP_DIR="$SMC_ROOT/backups"
            MGT_BACKUP_DIR_DEFAULTED=true
        fi

        if [[ -n "$MGT_BACKUP_DIR" ]] &&
           validate_source_dir "SGM" "$MGT_BACKUP_DIR"; then
            MGT_ENABLED=true
        fi
    else
        log INFO "source=SGM disabled reason=configuration_not_found_or_unreadable config=$MGT_CONFIG_FILE"
    fi

    if [[ -r "$LOG_CONFIG_FILE" ]]; then
        if property_exists "$LOG_CONFIG_FILE" "LOG_BACKUP_DIR"; then
            if raw="$(read_property "$LOG_CONFIG_FILE" "LOG_BACKUP_DIR")" &&
               resolved="$(resolve_forcepoint_path "$raw")"; then
                LOG_BACKUP_DIR="$resolved"
            else
                log WARN "source=SGL disabled reason=invalid_LOG_BACKUP_DIR config=$LOG_CONFIG_FILE"
            fi
        else
            LOG_BACKUP_DIR="$SMC_ROOT/backups"
            LOG_BACKUP_DIR_DEFAULTED=true
        fi

        if [[ -n "$LOG_BACKUP_DIR" ]] &&
           validate_source_dir "SGL" "$LOG_BACKUP_DIR"; then
            LOG_ENABLED=true
        fi
    else
        log INFO "source=SGL disabled reason=configuration_not_found_or_unreadable config=$LOG_CONFIG_FILE"
    fi

    if [[ "$MGT_ENABLED" != true && "$LOG_ENABLED" != true ]]; then
        die "No valid Management Server or Log Server backup source is available"
    fi

    if [[ "$MGT_ENABLED" == true ]]; then
        if [[ "$MGT_BACKUP_DIR_DEFAULTED" == true ]]; then
            log INFO "source=SGM path=$MGT_BACKUP_DIR path_source=default reason=SG_BACKUP_DIR_missing"
        else
            log INFO "source=SGM path=$MGT_BACKUP_DIR path_source=config config=$MGT_CONFIG_FILE"
        fi
    fi

    if [[ "$LOG_ENABLED" == true ]]; then
        if [[ "$LOG_BACKUP_DIR_DEFAULTED" == true ]]; then
            log INFO "source=SGL path=$LOG_BACKUP_DIR path_source=default reason=LOG_BACKUP_DIR_missing"
        else
            log INFO "source=SGL path=$LOG_BACKUP_DIR path_source=config config=$LOG_CONFIG_FILE"
        fi
    fi

    if [[ "$MGT_ENABLED" == true && "$LOG_ENABLED" == true &&
          "$MGT_BACKUP_DIR" == "$LOG_BACKUP_DIR" ]]; then
        log INFO "SGM and SGL backup directories are identical: $MGT_BACKUP_DIR"
    fi
}

acquire_mkdir_lock()
{
    local old_pid=""

    if mkdir -- "$LOCK_DIR" 2>/dev/null; then
        printf '%s\n' "$$" > "$LOCK_DIR/pid"
        LOCK_ACTIVE="mkdir"
        return 0
    fi

    if [[ -r "$LOCK_DIR/pid" ]]; then
        IFS= read -r old_pid < "$LOCK_DIR/pid" || true
    fi

    if [[ "$old_pid" =~ ^[0-9]+$ ]] && ! kill -0 "$old_pid" 2>/dev/null; then
        log WARN "Removing stale mkdir lock from pid=$old_pid path=$LOCK_DIR"
        rm -f -- "$LOCK_DIR/pid" 2>/dev/null || true
        rmdir -- "$LOCK_DIR" 2>/dev/null || true

        if mkdir -- "$LOCK_DIR" 2>/dev/null; then
            printf '%s\n' "$$" > "$LOCK_DIR/pid"
            LOCK_ACTIVE="mkdir"
            return 0
        fi
    fi

    return 1
}

acquire_lock()
{
    LOCK_FILE="/tmp/forcepoint-backup-cleanup-${UID}.lock"
    LOCK_DIR="/tmp/forcepoint-backup-cleanup-${UID}.lock.d"

    if [[ "$LOCK_METHOD" == "auto" ]]; then
        if command -v flock >/dev/null 2>&1; then
            LOCK_METHOD="flock"
        else
            LOCK_METHOD="mkdir"
        fi
    fi

    if [[ "$LOCK_METHOD" == "flock" ]]; then
        command -v flock >/dev/null 2>&1 ||
            die "flock was requested but is not installed"

        exec 9>"$LOCK_FILE"

        if ! flock -n 9; then
            log INFO "Another cleanup instance is already running. Exiting."
            exit 0
        fi

        LOCK_ACTIVE="flock"
        log INFO "lock_acquired method=flock path=$LOCK_FILE"
        return 0
    fi

    if ! acquire_mkdir_lock; then
        log INFO "Another cleanup instance is already running. Exiting."
        exit 0
    fi

    log INFO "lock_acquired method=mkdir path=$LOCK_DIR"
}

newest_candidate_mtime()
{
    local newest=0
    local path
    local value

    if [[ "$MGT_ENABLED" == true ]]; then
        for path in "$MGT_BACKUP_DIR"/sgm_*; do
            [[ -e "$path" ]] || continue
            value="$(stat -c '%Y' -- "$path" 2>/dev/null || printf '0')"
            [[ "$value" =~ ^[0-9]+$ ]] || value=0
            (( value > newest )) && newest="$value"
        done
    fi

    if [[ "$LOG_ENABLED" == true ]]; then
        for path in "$LOG_BACKUP_DIR"/sgl_*; do
            [[ -e "$path" ]] || continue
            value="$(stat -c '%Y' -- "$path" 2>/dev/null || printf '0')"
            [[ "$value" =~ ^[0-9]+$ ]] || value=0
            (( value > newest )) && newest="$value"
        done
    fi

    printf '%s\n' "$newest"
}

QUIET_REFERENCE_MTIME=0

wait_for_quiet_period()
{
    local started
    local now
    local newest
    local age
    local elapsed
    local announced=false

    if [[ "$SKIP_WAIT" == true || "$STABLE_AGE_SECONDS" -eq 0 ]]; then
        QUIET_REFERENCE_MTIME="$(newest_candidate_mtime)"
        log INFO "quiet_wait_skipped reference_mtime=$QUIET_REFERENCE_MTIME"
        return 0
    fi

    started="$(date +%s)"

    while true; do
        now="$(date +%s)"
        newest="$(newest_candidate_mtime)"

        if (( newest == 0 )); then
            QUIET_REFERENCE_MTIME=0
            log INFO "quiet_condition_met reason=no_existing_backup_entries"
            return 0
        fi

        age=$((now - newest))
        elapsed=$((now - started))

        if (( age >= STABLE_AGE_SECONDS )); then
            QUIET_REFERENCE_MTIME="$newest"
            log INFO "quiet_condition_met newest_entry_age_seconds=$age required_seconds=$STABLE_AGE_SECONDS"
            return 0
        fi

        if (( elapsed >= STABILITY_TIMEOUT_SECONDS )); then
            die "Backup directories did not become quiet within $STABILITY_TIMEOUT_SECONDS seconds"
        fi

        if [[ "$announced" != true ]]; then
            log INFO "Waiting for backup entries to become quiet: required_age_seconds=$STABLE_AGE_SECONDS timeout_seconds=$STABILITY_TIMEOUT_SECONDS"
            announced=true
        fi

        sleep "$POLL_SECONDS"
    done
}

SGL_PATHS=()
SGL_DATES=()
SGM_AUTO_PATHS=()
SGM_AUTO_DATES=()
SGM_MANUAL_PATHS=()
SGM_MANUAL_DATES=()

SGL_SORTED_DATES=()
SGM_SORTED_DATES=()
KEEP_SGL_DATE_LIST=()
KEEP_SGM_DATE_LIST=()

KEEP_SGL_PATHS=()
DELETE_SGL_PATHS=()
KEEP_SGM_AUTO_PATHS=()
DELETE_SGM_AUTO_PATHS=()
KEEP_SGM_MANUAL_PATHS=()
DELETE_SGM_MANUAL_PATHS=()

SGL_UNRECOGNIZED=0
SGM_UNRECOGNIZED=0

discover_backups()
{
    local path
    local backup_date

    shopt -s nullglob

    if [[ "$LOG_ENABLED" == true ]]; then
        for path in "$LOG_BACKUP_DIR"/sgl_*; do
            if backup_date="$(get_sgl_automatic_date "$path")"; then
                SGL_PATHS+=("$path")
                SGL_DATES+=("$backup_date")
            else
                ((SGL_UNRECOGNIZED += 1))
            fi
        done
    fi

    if [[ "$MGT_ENABLED" == true ]]; then
        for path in "$MGT_BACKUP_DIR"/sgm_*; do
            if backup_date="$(get_sgm_automatic_date "$path")"; then
                SGM_AUTO_PATHS+=("$path")
                SGM_AUTO_DATES+=("$backup_date")
            elif backup_date="$(get_sgm_manual_date "$path")"; then
                SGM_MANUAL_PATHS+=("$path")
                SGM_MANUAL_DATES+=("$backup_date")
            else
                ((SGM_UNRECOGNIZED += 1))
            fi
        done
    fi

    log INFO "discovery SGL_automatic=${#SGL_PATHS[@]} SGM_automatic=${#SGM_AUTO_PATHS[@]} SGM_manual=${#SGM_MANUAL_PATHS[@]} SGL_unrecognized=$SGL_UNRECOGNIZED SGM_unrecognized=$SGM_UNRECOGNIZED"
}

plan_cleanup()
{
    local i
    local cutoff=""
    local cutoff_index

    if (( ${#SGL_DATES[@]} > 0 )); then
        build_keep_dates "$KEEP_SGL_DATES" "${SGL_DATES[@]}"
        SGL_SORTED_DATES=("${SORTED_RESULT[@]}")
        KEEP_SGL_DATE_LIST=("${KEEP_RESULT[@]}")

        for i in "${!SGL_PATHS[@]}"; do
            if date_in_list "${SGL_DATES[$i]}" "${KEEP_SGL_DATE_LIST[@]}"; then
                KEEP_SGL_PATHS+=("${SGL_PATHS[$i]}")
            else
                DELETE_SGL_PATHS+=("${SGL_PATHS[$i]}")
            fi
        done
    fi

    if (( ${#SGM_AUTO_DATES[@]} > 0 )); then
        build_keep_dates "$KEEP_SGM_DATES" "${SGM_AUTO_DATES[@]}"
        SGM_SORTED_DATES=("${SORTED_RESULT[@]}")
        KEEP_SGM_DATE_LIST=("${KEEP_RESULT[@]}")

        for i in "${!SGM_AUTO_PATHS[@]}"; do
            if date_in_list "${SGM_AUTO_DATES[$i]}" "${KEEP_SGM_DATE_LIST[@]}"; then
                KEEP_SGM_AUTO_PATHS+=("${SGM_AUTO_PATHS[$i]}")
            else
                DELETE_SGM_AUTO_PATHS+=("${SGM_AUTO_PATHS[$i]}")
            fi
        done
    fi

    if (( ${#SGM_MANUAL_PATHS[@]} > 0 )); then
        if (( ${#SGM_SORTED_DATES[@]} >= KEEP_SGM_DATES &&
              ${#KEEP_SGM_DATE_LIST[@]} > 0 )); then
            cutoff_index=$((${#KEEP_SGM_DATE_LIST[@]} - 1))
            cutoff="${KEEP_SGM_DATE_LIST[$cutoff_index]}"

            for i in "${!SGM_MANUAL_PATHS[@]}"; do
                if [[ "${SGM_MANUAL_DATES[$i]}" < "$cutoff" ]]; then
                    DELETE_SGM_MANUAL_PATHS+=("${SGM_MANUAL_PATHS[$i]}")
                else
                    KEEP_SGM_MANUAL_PATHS+=("${SGM_MANUAL_PATHS[$i]}")
                fi
            done
        else
            KEEP_SGM_MANUAL_PATHS=("${SGM_MANUAL_PATHS[@]}")
        fi
    fi

    log INFO "PLAN SGL automatic: keep=${#KEEP_SGL_PATHS[@]} delete=${#DELETE_SGL_PATHS[@]} retained_dates=${#KEEP_SGL_DATE_LIST[@]}"
    log INFO "PLAN SGM automatic: keep=${#KEEP_SGM_AUTO_PATHS[@]} delete=${#DELETE_SGM_AUTO_PATHS[@]} retained_dates=${#KEEP_SGM_DATE_LIST[@]}"
    log INFO "PLAN SGM manual/commented: keep=${#KEEP_SGM_MANUAL_PATHS[@]} delete=${#DELETE_SGM_MANUAL_PATHS[@]} cutoff=${cutoff:-none}"
}

validate_plan()
{
    local total_delete
    local current_newest

    total_delete=$((${#DELETE_SGL_PATHS[@]} + ${#DELETE_SGM_AUTO_PATHS[@]} + ${#DELETE_SGM_MANUAL_PATHS[@]}))

    if (( MAX_DELETE_COUNT > 0 && total_delete > MAX_DELETE_COUNT )); then
        die "Safety limit exceeded: planned_deletions=$total_delete max_delete_count=$MAX_DELETE_COUNT"
    fi

    if (( ${#SGL_PATHS[@]} > 0 && ${#KEEP_SGL_PATHS[@]} == 0 )); then
        die "Safety invariant failed: SGL backups exist but none would remain"
    fi

    if (( ${#SGM_AUTO_PATHS[@]} > 0 && ${#KEEP_SGM_AUTO_PATHS[@]} == 0 )); then
        die "Safety invariant failed: SGM automatic backups exist but none would remain"
    fi

    if (( ${#SGL_SORTED_DATES[@]} < KEEP_SGL_DATES && ${#DELETE_SGL_PATHS[@]} > 0 )); then
        die "Safety invariant failed: SGL deletion planned before minimum retained dates exist"
    fi

    if (( ${#SGM_SORTED_DATES[@]} < KEEP_SGM_DATES && ${#DELETE_SGM_AUTO_PATHS[@]} > 0 )); then
        die "Safety invariant failed: SGM deletion planned before minimum retained dates exist"
    fi

    if (( ${#SGM_SORTED_DATES[@]} < KEEP_SGM_DATES && ${#DELETE_SGM_MANUAL_PATHS[@]} > 0 )); then
        die "Safety invariant failed: manual SGM deletion planned before minimum automatic dates exist"
    fi

    if [[ "$SKIP_WAIT" != true && "$STABLE_AGE_SECONDS" -gt 0 ]]; then
        current_newest="$(newest_candidate_mtime)"
        if (( current_newest > QUIET_REFERENCE_MTIME )); then
            die "A newer backup entry appeared after the quiet-period check; refusing deletion"
        fi
    fi

    log INFO "plan_validation_ok planned_deletions=$total_delete max_delete_count=$MAX_DELETE_COUNT"
}

safe_sgl_delete_target()
{
    local path="$1"

    [[ "$LOG_ENABLED" == true ]] || return 1
    [[ "$path" == "$LOG_BACKUP_DIR"/* ]] || return 1
    get_sgl_automatic_date "$path" >/dev/null
}

safe_sgm_delete_target()
{
    local path="$1"

    [[ "$MGT_ENABLED" == true ]] || return 1
    [[ "$path" == "$MGT_BACKUP_DIR"/* ]] || return 1

    if get_sgm_automatic_date "$path" >/dev/null; then
        return 0
    fi

    get_sgm_manual_date "$path" >/dev/null
}

log_keep_paths()
{
    local path

    for path in "${KEEP_SGL_PATHS[@]}"; do
        log INFO "KEEP SGL AUTOMATIC: $path"
    done

    for path in "${KEEP_SGM_AUTO_PATHS[@]}"; do
        log INFO "KEEP SGM AUTOMATIC: $path"
    done

    for path in "${KEEP_SGM_MANUAL_PATHS[@]}"; do
        log INFO "KEEP SGM MANUAL/COMMENTED: $path"
    done
}

execute_plan()
{
    local path
    local errors=0
    local sgl_deleted=0
    local sgm_auto_deleted=0
    local sgm_manual_deleted=0

    log_keep_paths

    if [[ "$DRY_RUN" == true ]]; then
        for path in "${DELETE_SGL_PATHS[@]}"; do
            log INFO "WOULD DELETE SGL AUTOMATIC: $path"
        done

        for path in "${DELETE_SGM_AUTO_PATHS[@]}"; do
            log INFO "WOULD DELETE SGM AUTOMATIC: $path"
        done

        for path in "${DELETE_SGM_MANUAL_PATHS[@]}"; do
            log INFO "WOULD DELETE SGM MANUAL/COMMENTED: $path"
        done

        log INFO "DRY RUN complete. SGL automatic: kept=${#KEEP_SGL_PATHS[@]} would_delete=${#DELETE_SGL_PATHS[@]}"
        log INFO "DRY RUN complete. SGM automatic: kept=${#KEEP_SGM_AUTO_PATHS[@]} would_delete=${#DELETE_SGM_AUTO_PATHS[@]}"
        log INFO "DRY RUN complete. SGM manual/commented: kept=${#KEEP_SGM_MANUAL_PATHS[@]} would_delete=${#DELETE_SGM_MANUAL_PATHS[@]}"
        return 0
    fi

    for path in "${DELETE_SGL_PATHS[@]}"; do
        if ! safe_sgl_delete_target "$path"; then
            log ERROR "Refusing unsafe SGL delete target: $path"
            ((errors += 1))
            continue
        fi

        if rm -rf -- "$path"; then
            log INFO "DELETE SGL AUTOMATIC: $path"
            ((sgl_deleted += 1))
        else
            log ERROR "Failed to delete SGL automatic backup: $path"
            ((errors += 1))
        fi
    done

    for path in "${DELETE_SGM_AUTO_PATHS[@]}"; do
        if ! safe_sgm_delete_target "$path"; then
            log ERROR "Refusing unsafe SGM automatic delete target: $path"
            ((errors += 1))
            continue
        fi

        if rm -f -- "$path"; then
            log INFO "DELETE SGM AUTOMATIC: $path"
            ((sgm_auto_deleted += 1))
        else
            log ERROR "Failed to delete SGM automatic backup: $path"
            ((errors += 1))
        fi
    done

    for path in "${DELETE_SGM_MANUAL_PATHS[@]}"; do
        if ! safe_sgm_delete_target "$path"; then
            log ERROR "Refusing unsafe SGM manual delete target: $path"
            ((errors += 1))
            continue
        fi

        if rm -f -- "$path"; then
            log INFO "DELETE SGM MANUAL/COMMENTED: $path"
            ((sgm_manual_deleted += 1))
        else
            log ERROR "Failed to delete SGM manual/commented backup: $path"
            ((errors += 1))
        fi
    done

    log INFO "Cleanup completed. SGL automatic: kept=${#KEEP_SGL_PATHS[@]} deleted=$sgl_deleted"
    log INFO "Cleanup completed. SGM automatic: kept=${#KEEP_SGM_AUTO_PATHS[@]} deleted=$sgm_auto_deleted"
    log INFO "Cleanup completed. SGM manual/commented: kept=${#KEEP_SGM_MANUAL_PATHS[@]} deleted=$sgm_manual_deleted"

    if (( errors > 0 )); then
        die "Cleanup completed with $errors deletion error(s)"
    fi
}

main()
{
    parse_args "$@"
    validate_options
    RUN_ID="$(date '+%Y%m%dT%H%M%S')-$$"

    check_runtime_dependencies

    log INFO "START script=$SCRIPT_NAME bash_version=$BASH_VERSION uid=$(id -u) gid=$(id -g) smc_root=$SMC_ROOT dry_run=$DRY_RUN keep_sgm_dates=$KEEP_SGM_DATES keep_sgl_dates=$KEEP_SGL_DATES max_delete_count=$MAX_DELETE_COUNT"
    log INFO "stability stable_age_seconds=$STABLE_AGE_SECONDS timeout_seconds=$STABILITY_TIMEOUT_SECONDS poll_seconds=$POLL_SECONDS skip_wait=$SKIP_WAIT"

    discover_sources
    acquire_lock
    wait_for_quiet_period
    discover_backups
    plan_cleanup
    validate_plan
    execute_plan

    log INFO "END status=success"
}

main "$@"
