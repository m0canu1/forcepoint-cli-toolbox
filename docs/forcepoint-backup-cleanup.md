# Forcepoint backup cleanup

`maintenance/forcepoint-backup-cleanup.sh` provides retention cleanup for Forcepoint Security Management Center backups.

The script is designed to be installed on the SMC server and configured in the SMC backup task through **Script to Execute After the Task**.

Normal execution is destructive. Always validate the target directory and run a dry run before enabling it in the scheduled task.

## What the script does

The script:

- reads the Management Server backup directory from `/usr/local/forcepoint/smc/data/SGConfiguration.txt` using `SG_BACKUP_DIR`, or falls back to `${SG_DATA_ROOT_DIR}/backups` when that property is absent;
- reads the Log Server backup directory from `/usr/local/forcepoint/smc/data/LogServerConfiguration.txt` using `LOG_BACKUP_DIR`;
- safely resolves the `SG_DATA_ROOT_DIR` token without sourcing either configuration file;
- keeps the 5 most recent distinct automatic Log Server backup dates;
- keeps the 5 most recent distinct automatic Management Server backup dates;
- deletes older recognized automatic backups;
- deletes manual/commented Management Server backups only when they are older than the oldest retained automatic Management Server backup;
- ignores files and directories that do not match the recognized Forcepoint backup naming patterns;
- uses `flock` to prevent overlapping cleanup executions;
- waits 60 seconds during normal post-task execution before evaluating retention.

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

The script fails without deleting anything if:

- either SMC configuration file is not readable;
- `LOG_BACKUP_DIR` is missing or empty;
- `SG_BACKUP_DIR` is present but empty or invalid;
- a backup path contains an unresolved `${...}` expression other than the supported `SG_DATA_ROOT_DIR` token;
- the configured path is not absolute;
- the configured path is `/`;
- the configured directory does not exist;
- the configured directory is not readable or traversable;
- the configured directory is not writable during a real cleanup run;
- `flock` is unavailable.

A `--dry-run` does not require write access to the backup directory.

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

The script itself includes the 60-second delay used for post-task execution, so the SMC configuration does not need a separate delay.

## Why the script uses a lock and a delay

A backup task containing multiple targets can cause Forcepoint to invoke the post-task script more than once.

The script therefore:

1. acquires a non-blocking `flock` lock;
2. lets only one cleanup instance continue;
3. waits 60 seconds;
4. evaluates retention after the other backup target has had time to finish.

A second overlapping invocation exits without deleting anything.

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

The script writes to standard output and, when `logger` is available, uses the syslog tag:

~~~text
forcepoint-backup-cleanup
~~~

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
