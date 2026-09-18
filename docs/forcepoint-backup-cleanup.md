# Forcepoint backup cleanup

`maintenance/forcepoint-backup-cleanup.sh` provides retention cleanup for Forcepoint Security Management Center backups.

The script is designed to be installed on the SMC server and configured in the SMC backup task through **Script to Execute After the Task**.

Normal execution is destructive. Always validate the target directory and run a dry run before enabling it in the scheduled task.

## What the script does

The script:

- discovers Management Server and Log Server backup sources independently, so either role can be absent;
- reads `SG_BACKUP_DIR` and `LOG_BACKUP_DIR` without sourcing Forcepoint configuration files;
- supports an alternative SMC root with `--smc-root` or `FORCEPOINT_SMC_ROOT`;
- falls back to `${SG_DATA_ROOT_DIR}/backups` when the relevant backup-directory property is absent;
- keeps 5 distinct automatic SGM and SGL dates by default, with independent configurable retention;
- separates discovery, retention planning, safety validation, and deletion;
- refuses a run if the deletion plan exceeds the configured safety threshold;
- waits for backup entries to reach a quiet age instead of relying on a fixed 60-second sleep;
- uses `flock` when available and falls back to an atomic `mkdir` lock;
- ignores unrecognized entries and symbolic links;
- assigns a run ID to every execution and logs to stdout, syslog/journal, and optionally a file;
- retains manual/commented SGM backups until enough automatic SGM dates exist and they are older than the retained cutoff.

Retention for Log Server (`sgl`) and Management Server (`sgm`) backups is intentionally evaluated independently. A successful Log Server backup therefore cannot advance Management Server retention when the Management Server backup did not complete.

## Backup directory discovery

The Management Server and Log Server backup paths are discovered independently.

Management Server configuration:

~~~text
/usr/local/forcepoint/smc/data/SGConfiguration.txt
SG_BACKUP_DIR=/mnt/win_share/Backup
~~~

If `SG_BACKUP_DIR` is **not present** in `SGConfiguration.txt`, the script uses the Forcepoint default backup directory:

~~~text
${SG_DATA_ROOT_DIR}/backups
~~~

With the standard installation path this resolves to:

~~~text
/usr/local/forcepoint/smc/backups
~~~

The fallback is used only when the `SG_BACKUP_DIR` key is absent. If the key exists but its value is empty or invalid, the script stops instead of silently ignoring the configuration.

Log Server configuration:

~~~text
/usr/local/forcepoint/smc/data/LogServerConfiguration.txt
LOG_BACKUP_DIR=${SG_DATA_ROOT_DIR}/backups
~~~

The `SG_DATA_ROOT_DIR` token is resolved from the SMC installation root. With the standard installation path this becomes:

~~~text
/usr/local/forcepoint/smc/backups
~~~

The configuration files are **not sourced or evaluated as shell code**. Only the required properties are parsed.

You can verify both values with:

~~~bash
grep -E '^[[:space:]]*SG_BACKUP_DIR[[:space:]]*=' \
    /usr/local/forcepoint/smc/data/SGConfiguration.txt

grep -E '^[[:space:]]*LOG_BACKUP_DIR[[:space:]]*=' \
    /usr/local/forcepoint/smc/data/LogServerConfiguration.txt
~~~

`ARCHIVE_DIR_1` is not used for backup retention; it is a log archive location, not the Log Server backup directory.

Do not copy the complete `SGConfiguration.txt` into issues, tickets, or public logs.

Management Server and Log Server sources are evaluated independently. A missing or unusable configuration disables that source and is logged. The script stops only when **no valid source remains**.

For a configured source, the script rejects unresolved variables, non-absolute paths, `/`, unreadable directories, and unwritable directories during a real cleanup run. A `--dry-run` does not require write access.

Only the known `SG_DATA_ROOT_DIR` token is expanded. The configuration files are never sourced and their contents are never passed to `eval`.

## Recognized backups

### Log Server automatic backups

Recognized form:

~~~text
sgl_v7.3.1.11715_20260201_230000_Backup giornaliero no Log Files_no_logs_zip
~~~

These are directories stored under the resolved `LOG_BACKUP_DIR`. The script accepts both names without a description and names containing a description between the timestamp and `_no_logs_zip`. It keeps the five most recent distinct SGL backup dates and removes older recognized SGL backup directories.

### Management Server automatic backups

Recognized form:

~~~text
sgm_v7.4.1.12025_20260915_070000.zip
~~~

These are files. The script keeps the five most recent distinct SGM backup dates and removes older recognized SGM automatic backup files.

### Manual or commented Management Server backups

Recognized form:

~~~text
sgm_v7.4.1.12025_20260914_091603_Performed before Update Package 2065 activation.zip
~~~

Manual/commented SGM backups are deleted only when both conditions are true:

1. at least five distinct automatic SGM backup dates exist;
2. the manual/commented backup date is older than the oldest of the five retained automatic SGM dates.

If fewer than five automatic SGM dates exist, manual/commented SGM backups are not deleted.

Unrecognized entries are ignored. For example:

~~~text
sgrollbackfolder
~~~

is never selected for deletion.

## Compatibility and observed SMC behavior

The cleanup logic is Bash-based. The script includes a POSIX-compatible bootstrap so it can also survive SMC versions that explicitly start the configured post-task script through `/bin/sh`.

The following behavior has been observed in the tested environments:

| SMC version | Observed post-task behavior | Result |
| --- | --- | --- |
| 7.3.4 | The task runner invoked `sh /usr/local/sbin/forcepoint-backup-cleanup.sh ...` | Requires the Bash re-exec bootstrap included in the current script |
| 7.4.1 | The cleanup script ran successfully without the observed `/bin/sh` incompatibility | Current script works |

These are environment observations, not a guarantee that every installation of the same SMC version uses an identical task-runner implementation. After an SMC upgrade, validate the post-task execution path with a dry run before relying on automatic deletion.

On the tested 7.3.4 system, the SMC task log showed:

~~~text
Task script command: sh /usr/local/sbin/forcepoint-backup-cleanup.sh 1>>script.out 2>>script.err
~~~

Without the bootstrap, this caused:

~~~text
/usr/local/sbin/forcepoint-backup-cleanup.sh: 3: set: Illegal option -o pipefail
~~~

because the shell selected as `/bin/sh` did not support Bash's `pipefail` option. The current script detects that it was not started by Bash and immediately performs:

~~~text
exec bash "$0" "$@"
~~~

before any Bash-only syntax is evaluated.

For compatibility testing, both invocation forms should succeed:

~~~bash
sudo -u sgadmin sh /usr/local/sbin/forcepoint-backup-cleanup.sh \
    --dry-run --no-wait

sudo -u sgadmin bash /usr/local/sbin/forcepoint-backup-cleanup.sh \
    --dry-run --no-wait
~~~

## Runtime requirements on Ubuntu

The target systems are expected to be Ubuntu-based. The script requires Bash 3 or newer and standard GNU userland commands such as `sort`, `stat`, `date`, `rm`, and `mkdir`.

On a minimal Ubuntu installation, the relevant packages can be installed with:

~~~bash
sudo apt-get update
sudo apt-get install -y bash coreutils util-linux
~~~

`flock` is provided by `util-linux`. It is preferred when available, but it is no longer mandatory: `--lock-method auto` falls back to an atomic `mkdir` lock.

The script no longer depends on `mapfile` or associative arrays. `logger` is optional; stdout logging continues even when syslog tooling is unavailable.

## Recommended installation path

Install the script as:

~~~text
/usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

Using a stable absolute path is important because the SMC post-task process can start with a different working directory.

From a checkout of this repository:

~~~bash
sudo install -o root -g root -m 0755 \
    maintenance/forcepoint-backup-cleanup.sh \
    /usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

Verify the installed file:

~~~bash
ls -l /usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

Expected permissions are similar to:

~~~text
-rwxr-xr-x root root ... /usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

The script is owned by `root` so the SMC service account can execute it but cannot modify it.

## Verify the SMC execution account

Before enabling deletion, verify which account Forcepoint uses for the post-task hook.

Create a temporary test script:

~~~bash
sudo tee /usr/local/sbin/forcepoint-post-backup-test.sh >/dev/null <<'EOF'
#!/usr/bin/env bash

{
    echo "======================================"
    date
    id
    pwd
    echo "======================================"
} >> /tmp/forcepoint-post-backup-test.log
EOF

sudo chown root:root /usr/local/sbin/forcepoint-post-backup-test.sh
sudo chmod 0755 /usr/local/sbin/forcepoint-post-backup-test.sh
~~~

Temporarily configure the SMC backup task **Script to Execute After the Task** field with:

~~~text
/usr/local/sbin/forcepoint-post-backup-test.sh
~~~

Run the backup task once, then inspect:

~~~bash
cat /tmp/forcepoint-post-backup-test.log
~~~

A typical SMC installation may show an execution account such as `sgadmin`. Use the account shown by your system for the permission tests below.

After the test:

~~~bash
sudo rm -f /usr/local/sbin/forcepoint-post-backup-test.sh
~~~

## Check permissions

If the post-task hook runs as `sgadmin`, verify that it can read the SMC configuration file:

~~~bash
sudo -u sgadmin test -r /usr/local/forcepoint/smc/data/SGConfiguration.txt \
    && echo "SGConfiguration.txt: READ OK"
~~~

Then run the cleanup dry run as the same account:

~~~bash
sudo -u sgadmin /usr/local/sbin/forcepoint-backup-cleanup.sh \
    --dry-run --no-wait
~~~

This verifies that the account can:

1. read both `SGConfiguration.txt` and `LogServerConfiguration.txt`;
2. discover `SG_BACKUP_DIR`;
3. resolve `LOG_BACKUP_DIR`;
4. enumerate both backup directories;
5. identify which SGM and SGL backups would be kept or deleted.

Because this is a dry run, nothing is removed.

## Configuration options

Defaults are conservative and require no arguments from the SMC task:

~~~text
SGM retained dates:        5
SGL retained dates:        5
maximum planned deletions: 500
quiet age:                 30 seconds
quiet timeout:             180 seconds
poll interval:             5 seconds
lock method:               auto
~~~

Useful overrides include:

~~~bash
--smc-root /usr/local/forcepoint/smc
--management-config /path/to/SGConfiguration.txt
--log-config /path/to/LogServerConfiguration.txt
--keep-dates 7
--keep-sgm-dates 10
--keep-sgl-dates 5
--max-delete-count 250
--stable-age-seconds 45
--stability-timeout-seconds 300
--poll-seconds 5
--lock-method auto
--log-file /var/log/forcepoint-backup-cleanup.log
~~~

Set `--max-delete-count 0` only when you deliberately want to disable the count threshold.

`--no-wait` skips the quiet-period protection and is intended for controlled testing, especially with `--dry-run`.

## Test the retention policy

Before configuring the SMC task, run:

~~~bash
sudo -u sgadmin /usr/local/sbin/forcepoint-backup-cleanup.sh \
    --dry-run --no-wait
~~~

Typical output includes lines similar to:

~~~text
Using SGM backup directory from /usr/local/forcepoint/smc/data/SGConfiguration.txt: /mnt/win_share/Backup
Using SGL backup directory from /usr/local/forcepoint/smc/data/LogServerConfiguration.txt: /usr/local/forcepoint/smc/backups
DRY RUN enabled. No files or directories will be deleted.
Keeping SGL automatic backup dates: 20260918 20260917 20260916 20260915 20260914
Keeping SGM automatic backup dates: 20260918 20260917 20260916 20260915 20260914
WOULD DELETE SGL AUTOMATIC: /usr/local/forcepoint/smc/backups/sgl_..._20260913_230000_Backup giornaliero no Log Files_no_logs_zip
WOULD DELETE SGM AUTOMATIC: /mnt/win_share/Backup/sgm_..._20260913_070000.zip
~~~

Review every `WOULD DELETE` entry before enabling normal execution.

Do not use `--no-wait` for the scheduled SMC post-task. It exists primarily for manual testing.

## Configure the Forcepoint SMC backup task

After the dry run has been reviewed:

1. Open the existing scheduled SMC backup task.
2. Edit the task parameters.
3. Locate **Script to Execute After the Task**.
4. Set the field to:

~~~text
/usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

5. Save the task.
6. Run the backup task manually once, or wait for the next scheduled execution.
7. Verify the cleanup logs and the contents of the configured backup directory.

No command-line arguments are required in the SMC field. Normal execution performs the real cleanup.

Forcepoint may wrap the configured command and invoke it explicitly through `sh`, for example:

~~~text
sh /usr/local/sbin/forcepoint-backup-cleanup.sh 1>>script.out 2>>script.err
~~~

The cleanup script therefore contains a small POSIX-compatible bootstrap at the top. If it was started by `sh`, it immediately re-executes itself with Bash before any Bash-only syntax such as `set -o pipefail`, `[[ ... ]]`, associative arrays, or `mapfile` is evaluated.

The script performs its own quiet-period check before planning deletions, so the SMC configuration does not need a separate delay.

## Concurrency and quiet-period protection

A backup task containing multiple targets can cause Forcepoint to invoke the post-task script more than once.

The script acquires a non-blocking lock before doing retention work. In `auto` mode it uses `flock` when available and otherwise uses an atomic `mkdir` lock with stale-PID recovery. A second overlapping invocation exits without deleting anything.

Instead of sleeping for a fixed number of seconds, the script checks the newest SGM/SGL candidate modification time and waits until it has been quiet for `--stable-age-seconds`. It aborts after `--stability-timeout-seconds` if the directories never become quiet. Before deletion, it also refuses the plan if a newer candidate appeared after the quiet-period check.

## Safety model

Before any deletion, the script first discovers recognized backups and builds an in-memory plan. It then validates the whole plan.

The default `--max-delete-count 500` prevents an unexpectedly large cleanup from starting. The script also refuses automatic deletion if its retention invariants would leave no automatic backup, or if a deletion were planned before the requested number of distinct retained dates exists.

Every delete target is validated again immediately before `rm`: it must still be a direct candidate under the resolved source directory, match the expected SGM/SGL naming form, and not be a symbolic link.

Unknown filenames are counted for diagnostics but never selected for deletion.

## First production run

After configuring the SMC task, monitor the cleanup log:

~~~bash
journalctl -t forcepoint-backup-cleanup -f
~~~

Then trigger the backup task.

After it completes, verify the retained backups in both the configured Management Server backup directory and the resolved Log Server backup directory.

The expected result is:

- the five most recent distinct SGL automatic backup dates remain;
- the five most recent distinct SGM automatic backup dates remain;
- older recognized automatic backups are removed;
- manual/commented SGM backups older than the SGM cutoff are removed;
- recent manual/commented backups remain;
- unrecognized items such as `sgrollbackfolder` remain untouched.

## Manual execution

Preview only:

~~~bash
/usr/local/sbin/forcepoint-backup-cleanup.sh --dry-run --no-wait
~~~

Real cleanup without the post-task delay:

~~~bash
/usr/local/sbin/forcepoint-backup-cleanup.sh --no-wait
~~~

Normal production behavior:

~~~bash
/usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

Show help:

~~~bash
/usr/local/sbin/forcepoint-backup-cleanup.sh --help
~~~

## Logging

Every run gets an identifier such as `20260918T115629-156684`. Log lines include `run_id` and a level so overlapping or historical executions can be correlated.

The script always writes to standard output. When `logger` is available it also uses the syslog tag:

~~~text
forcepoint-backup-cleanup
~~~

An additional file can be configured with `--log-file /absolute/path`.

Useful commands:

~~~bash
journalctl -t forcepoint-backup-cleanup
journalctl -t forcepoint-backup-cleanup -n 100
journalctl -t forcepoint-backup-cleanup -f
~~~

## Troubleshooting

### Check cleanup logs with journalctl

The script writes messages with the syslog tag:

~~~text
forcepoint-backup-cleanup
~~~

Show all available cleanup messages:

~~~bash
journalctl -t forcepoint-backup-cleanup
~~~

Show the latest 100 messages without opening a pager:

~~~bash
journalctl -t forcepoint-backup-cleanup -n 100 --no-pager
~~~

Show only messages from today:

~~~bash
journalctl -t forcepoint-backup-cleanup --since today
~~~

Follow the cleanup while triggering the SMC backup task:

~~~bash
journalctl -t forcepoint-backup-cleanup -f
~~~

If the system forwards syslog to traditional files, also check:

~~~bash
grep 'forcepoint-backup-cleanup' /var/log/messages
~~~

If neither command shows anything, first verify that the script runs manually as the same account used by the SMC post-task hook.

### Verify that the SMC actually executes the script

Confirm the configured path in **Script to Execute After the Task** is exactly:

~~~text
/usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

Check the installed script:

~~~bash
ls -l /usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

Expected permissions are similar to:

~~~text
-rwxr-xr-x root root ... /usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

Run it manually as the post-task account:

~~~bash
sudo -u sgadmin /usr/local/sbin/forcepoint-backup-cleanup.sh \
    --dry-run --no-wait
~~~

If manual execution works but no log entry appears when the SMC task runs, temporarily use the execution-account test script documented above to confirm that the SMC is invoking the configured post-task path.

### Forcepoint runs the script with sh

If the SMC task log contains a command similar to:

~~~text
Task script command: sh /usr/local/sbin/forcepoint-backup-cleanup.sh 1>>script.out 2>>script.err
~~~

that is expected. Forcepoint is explicitly starting the configured script through `sh`.

Older versions of this cleanup script could fail immediately with:

~~~text
set: Illegal option -o pipefail
~~~

because `/bin/sh` may not be Bash. The current script detects this condition and re-executes itself using `bash`.

To reproduce the SMC invocation path without deleting anything:

~~~bash
sudo -u sgadmin sh /usr/local/sbin/forcepoint-backup-cleanup.sh \
    --dry-run --no-wait
~~~

This must behave the same as:

~~~bash
sudo -u sgadmin bash /usr/local/sbin/forcepoint-backup-cleanup.sh \
    --dry-run --no-wait
~~~

Check which shell `/bin/sh` points to with:

~~~bash
readlink -f /bin/sh
~~~

If the SMC redirects output to relative files such as `script.out` and `script.err`, inspect the SMC script working directory or locate them with:

~~~bash
find /usr/local/forcepoint/smc \
    \( -name script.out -o -name script.err \) \
    -ls
~~~

### Check Forcepoint task output and task status

Some SMC versions redirect the post-task script's standard output and standard error to relative files such as:

~~~text
script.out
script.err
~~~

On the tested system these files were available from the SMC script working area. If the exact location is unclear, locate them with:

~~~bash
find /usr/local/forcepoint/smc \
    \( -name script.out -o -name script.err \) \
    -ls
~~~

Inspect the latest output with:

~~~bash
tail -n 100 script.out
tail -n 100 script.err
~~~

Because Forcepoint can use append redirection (`>>`), these files may contain errors from older executions. A stale historical error does not by itself mean the latest run failed.

The SMC can also keep a task-status history in a file such as `backup_script_log.txt`. Locate it if necessary:

~~~bash
find /usr/local/forcepoint/smc -name backup_script_log.txt -ls
~~~

Then inspect the most recent records:

~~~bash
tail -n 100 backup_script_log.txt
~~~

A successful execution is represented by a final record similar to:

~~~text
Operation          : SCRIPT AFTER TASK
Script name        : /usr/local/sbin/forcepoint-backup-cleanup.sh
Status             : OK
~~~

When troubleshooting, correlate three sources for the same execution time:

1. the SMC task log, which shows how the command was invoked;
2. `script.out` / `script.err`, which capture the post-task process output;
3. `journalctl -t forcepoint-backup-cleanup`, which contains the cleanup script's own log messages.

After troubleshooting, the append-only `script.out` and `script.err` files can optionally be truncated if operational policy allows it:

~~~bash
truncate -s 0 script.out script.err
~~~

### Verify backup directory discovery

Check the Management Server setting:

~~~bash
grep -E '^[[:space:]]*SG_BACKUP_DIR[[:space:]]*=' \
    /usr/local/forcepoint/smc/data/SGConfiguration.txt
~~~

Check the Log Server setting:

~~~bash
grep -E '^[[:space:]]*LOG_BACKUP_DIR[[:space:]]*=' \
    /usr/local/forcepoint/smc/data/LogServerConfiguration.txt
~~~

For example:

~~~text
SG_BACKUP_DIR=/mnt/win_share/Backup
LOG_BACKUP_DIR=${SG_DATA_ROOT_DIR}/backups
~~~

With the standard SMC installation path, the second value resolves to:

~~~text
/usr/local/forcepoint/smc/backups
~~~

A normal dry run with an explicit Management Server path should contain lines similar to:

~~~text
Using SGM backup directory from /usr/local/forcepoint/smc/data/SGConfiguration.txt: /mnt/win_share/Backup
Using SGL backup directory from /usr/local/forcepoint/smc/data/LogServerConfiguration.txt: /usr/local/forcepoint/smc/backups
~~~

If `SG_BACKUP_DIR` is absent, the script logs the fallback explicitly:

~~~text
SG_BACKUP_DIR not found in /usr/local/forcepoint/smc/data/SGConfiguration.txt; using default SGM backup directory: /usr/local/forcepoint/smc/backups
~~~

If the script reports an unresolved variable expression, inspect the configured value. Only the expected `${SG_DATA_ROOT_DIR}` token is resolved automatically; unexpected variable expressions cause the script to stop without deleting anything.

If `grep` returns no `SG_BACKUP_DIR` line, that is valid: the script uses `${SG_DATA_ROOT_DIR}/backups` for Management Server backups and reports that fallback in the journal.

### Verify permissions as the post-task account

For an SMC where the hook runs as `sgadmin`:

~~~bash
sudo -u sgadmin test -r /usr/local/forcepoint/smc/data/SGConfiguration.txt \
    && echo "SGConfiguration.txt: READ OK"

sudo -u sgadmin test -r /usr/local/forcepoint/smc/data/LogServerConfiguration.txt \
    && echo "LogServerConfiguration.txt: READ OK"
~~~

Check the Management Server backup directory:

~~~bash
sudo -u sgadmin test -r /mnt/win_share/Backup && echo "SGM: READ OK"
sudo -u sgadmin test -x /mnt/win_share/Backup && echo "SGM: TRAVERSE OK"
sudo -u sgadmin test -w /mnt/win_share/Backup && echo "SGM: WRITE OK"
~~~

Check the Log Server backup directory:

~~~bash
sudo -u sgadmin test -r /usr/local/forcepoint/smc/backups && echo "SGL: READ OK"
sudo -u sgadmin test -x /usr/local/forcepoint/smc/backups && echo "SGL: TRAVERSE OK"
sudo -u sgadmin test -w /usr/local/forcepoint/smc/backups && echo "SGL: WRITE OK"
~~~

If your configured directories are different, replace the example paths with the values reported by the cleanup script.

Useful read-only filesystem checks are:

~~~bash
ls -ld /mnt/win_share/Backup
ls -ld /usr/local/forcepoint/smc/backups

findmnt -T /mnt/win_share/Backup
findmnt -T /usr/local/forcepoint/smc/backups
~~~

A dry run requires read and traverse access. A real cleanup additionally requires write access.

### No SGL backups are detected

If the summary contains:

~~~text
SGL automatic: kept=0 would_delete=0
~~~

first confirm that the Log Server directory contains backup directories:

~~~bash
find /usr/local/forcepoint/smc/backups \
    -maxdepth 1 \
    -type d \
    -name 'sgl_*' \
    -printf '%f\n' | sort | tail -20
~~~

Recognized names include both:

~~~text
sgl_v7.4.1.12025_20260918_070000_no_logs_zip
~~~

and names containing a description:

~~~text
sgl_v7.3.1.11715_20260201_230000_Backup giornaliero no Log Files_no_logs_zip
~~~

The entry must be a directory, contain a `YYYYMMDD_HHMMSS` timestamp, and end in `_no_logs_zip`.

If SGL directories exist but none are detected, compare their names with these forms before changing the matching expression.

### No SGM backups are detected

If the summary contains:

~~~text
SGM automatic: kept=0 would_delete=0
~~~

inspect the configured Management Server backup directory:

~~~bash
find /mnt/win_share/Backup \
    -maxdepth 1 \
    -type f \
    -name 'sgm_*' \
    -printf '%f\n' | sort | tail -20
~~~

An automatic SGM backup must look like:

~~~text
sgm_v7.3.4.11739_20260918_095643.zip
~~~

A manual/commented backup contains additional text after the timestamp, for example:

~~~text
sgm_v7.3.4.11739_20260917_071257_Performed before Update Package 2067 activation.zip
~~~

Manual/commented backups do not count toward the five automatic SGM dates.

### More than five files are kept

Retention is based on **five distinct backup dates**, not five files.

If two automatic backups exist on the same retained date, both are kept. For example:

~~~text
sgm_..._20260918_095643.zip
sgm_..._20260918_103659.zip
~~~

Both belong to the retained date `20260918`, so a summary can legitimately report more than five kept files.

### "Another cleanup instance is already running"

The message:

~~~text
Another cleanup instance is already running. Exiting.
~~~

is normally harmless. An SMC task with multiple targets can invoke the post-task script more than once. The first process holds the `flock` lock while it waits and performs cleanup; an overlapping invocation exits.

Check whether a cleanup process is active:

~~~bash
pgrep -af forcepoint-backup-cleanup.sh
~~~

The lock file itself can remain present under `/tmp` after execution. Its presence does **not** mean the lock is still held; `flock` releases the lock when the process exits.

### The script reports that flock is missing

Check availability with:

~~~bash
command -v flock
~~~

The cleanup intentionally refuses to run without `flock`, because concurrent post-task executions could otherwise process the backup directories at the same time.

Do not add or replace system packages on a Forcepoint SMC solely to satisfy this dependency without first checking the supported appliance maintenance procedure.

### Deletion fails but dry-run works

If the dry run succeeds but a real cleanup reports deletion errors:

1. verify write access as the SMC execution account;
2. check whether the Management Server path is a network mount;
3. inspect mount state and options;
4. confirm that the files/directories are owned or writable as expected.

Useful commands:

~~~bash
ls -ld /mnt/win_share/Backup
findmnt -T /mnt/win_share/Backup

ls -ld /usr/local/forcepoint/smc/backups
findmnt -T /usr/local/forcepoint/smc/backups
~~~

Then reproduce the selection without deleting anything:

~~~bash
sudo -u sgadmin /usr/local/sbin/forcepoint-backup-cleanup.sh \
    --dry-run --no-wait
~~~

Do not manually remove backups until the path, retention selection, and permission problem have been understood.

## Automated tests

CI now exercises more than syntax and ShellCheck. The functional test suite creates temporary SMC layouts and validates:

- invocation through `sh` and the Bash bootstrap;
- Management-only and Log-only installations;
- missing `SG_BACKUP_DIR` fallback;
- `${SG_DATA_ROOT_DIR}` expansion;
- identical SGM/SGL directories;
- multiple backups on the same retained date;
- manual/commented SGM cutoff behavior;
- configurable retention;
- deletion-count safety limits;
- optional file logging and run IDs.

Run the suite from a repository checkout with:

~~~bash
bash .github/scripts/test-forcepoint-backup-cleanup.sh
~~~

## Updating the installed script

After pulling a newer repository version, reinstall it:

~~~bash
sudo install -o root -g root -m 0755 \
    maintenance/forcepoint-backup-cleanup.sh \
    /usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

Then run another dry run as the SMC execution account:

~~~bash
sudo -u sgadmin /usr/local/sbin/forcepoint-backup-cleanup.sh \
    --dry-run --no-wait
~~~

## Disable or remove the cleanup

To stop automatic cleanup:

1. edit the SMC backup task;
2. clear **Script to Execute After the Task** or restore the previous post-task script;
3. save the task.

After the SMC task no longer references it, remove the installed script if desired:

~~~bash
sudo rm -f /usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

## Important limitations

The filename matching is intentionally strict. Files and directories that do not match the documented Forcepoint backup naming forms are not deleted.

If a future Forcepoint SMC release changes backup naming, review and update the matching expressions before relying on cleanup for the new format.

The cleanup operates only on entries directly inside the resolved Management Server and Log Server backup directories; it does not recursively search unrelated directory trees for backup names.
