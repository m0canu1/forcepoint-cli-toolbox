# SMC backup cleanup

`maintenance/cleanup-smc-backups.sh` provides retention cleanup for Forcepoint Security Management Center backups.

The script is designed to be installed on the SMC server and configured in the SMC backup task through **Script to Execute After the Task**.

Normal execution is destructive. Always validate the target directory and run a dry run before enabling it in the scheduled task.

## What the script does

The script:

- reads the SMC backup directory from `/usr/local/forcepoint/smc/data/SGConfiguration.txt`;
- keeps the 5 most recent distinct automatic Log Server backup dates;
- keeps the 5 most recent distinct automatic Management Server backup dates;
- deletes older recognized automatic backups;
- deletes manual/commented Management Server backups only when they are older than the oldest retained automatic Management Server backup;
- ignores files and directories that do not match the recognized Forcepoint backup naming patterns;
- uses `flock` to prevent overlapping cleanup executions;
- waits 60 seconds during normal post-task execution before evaluating retention.

Retention for Log Server (`sgl`) and Management Server (`sgm`) backups is intentionally evaluated independently. A successful Log Server backup therefore cannot advance Management Server retention when the Management Server backup did not complete.

## Backup directory discovery

The backup path is not hard-coded.

The script reads:

~~~text
/usr/local/forcepoint/smc/data/SGConfiguration.txt
~~~

and extracts only the `SG_BACKUP_DIR` property, for example:

~~~text
SG_BACKUP_DIR=/mnt/win_share/Backup
~~~

or:

~~~text
SG_BACKUP_DIR=/usr/local/forcepoint/smc/backups
~~~

The configuration file is **not sourced or evaluated as shell code**. The script parses only the `SG_BACKUP_DIR` line because the file contains many unrelated SMC settings and can contain sensitive values.

You can verify the configured backup path with:

~~~bash
grep -E '^[[:space:]]*SG_BACKUP_DIR[[:space:]]*='     /usr/local/forcepoint/smc/data/SGConfiguration.txt
~~~

Do not copy the complete `SGConfiguration.txt` into issues, tickets, or public logs.

The script fails without deleting anything if:

- `SGConfiguration.txt` is not readable;
- `SG_BACKUP_DIR` is missing or empty;
- `SG_BACKUP_DIR` contains an unresolved `${...}` expression;
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
sgl_v7.4.1.12025_20260915_070000_no_logs_zip
~~~

These are directories. The script keeps the five most recent distinct SGL backup dates and removes older recognized SGL backup directories.

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
sudo install -o root -g root -m 0755     maintenance/cleanup-smc-backups.sh     /usr/local/sbin/forcepoint-backup-cleanup.sh
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
sudo -u sgadmin test -r /usr/local/forcepoint/smc/data/SGConfiguration.txt     && echo "SGConfiguration.txt: READ OK"
~~~

Then run the cleanup dry run as the same account:

~~~bash
sudo -u sgadmin /usr/local/sbin/forcepoint-backup-cleanup.sh     --dry-run --no-wait
~~~

This verifies that the account can:

1. read `SGConfiguration.txt`;
2. discover `SG_BACKUP_DIR`;
3. enumerate the backup directory;
4. identify which backups would be kept or deleted.

Because this is a dry run, nothing is removed.

## Test the retention policy

Before configuring the SMC task, run:

~~~bash
sudo -u sgadmin /usr/local/sbin/forcepoint-backup-cleanup.sh     --dry-run --no-wait
~~~

Typical output includes lines similar to:

~~~text
Using SG_BACKUP_DIR from /usr/local/forcepoint/smc/data/SGConfiguration.txt: /mnt/win_share/Backup
DRY RUN enabled. No files or directories will be deleted.
Keeping SGL automatic backup dates: 20260918 20260917 20260916 20260915 20260914
Keeping SGM automatic backup dates: 20260918 20260917 20260916 20260915 20260914
WOULD DELETE SGL AUTOMATIC: /mnt/win_share/Backup/sgl_..._20260913_070000_no_logs_zip
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

After it completes, verify the retained backups in the configured `SG_BACKUP_DIR`.

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

## Updating the installed script

After pulling a newer repository version, reinstall it:

~~~bash
sudo install -o root -g root -m 0755     maintenance/cleanup-smc-backups.sh     /usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

Then run another dry run as the SMC execution account:

~~~bash
sudo -u sgadmin /usr/local/sbin/forcepoint-backup-cleanup.sh     --dry-run --no-wait
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

The cleanup operates only on entries directly inside `SG_BACKUP_DIR`; it does not recursively search unrelated directory trees for backup names.
