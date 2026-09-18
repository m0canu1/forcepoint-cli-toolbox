# SMC backup cleanup

`maintenance/cleanup-smc-backups.sh` provides retention cleanup for Forcepoint Security Management Center backups.

The script is intended for the SMC **Script to Execute After the Task** hook. It is destructive by default, so test it with `--dry-run --no-wait` before enabling it in a scheduled backup task.

## Backup directory discovery

The backup path is not hard-coded.

The script reads:

`/usr/local/forcepoint/smc/data/SGConfiguration.txt`

and extracts only the `SG_BACKUP_DIR` property, for example:

~~~text
SG_BACKUP_DIR=/mnt/win_share/Backup
~~~

The configuration file is **not sourced or evaluated as shell code**. This is intentional because the file contains unrelated configuration values that can include sensitive data. Leading/trailing whitespace is trimmed, and a path enclosed in matching single or double quotes is accepted.

The script fails without deleting anything if:

- `SGConfiguration.txt` is not readable;
- `SG_BACKUP_DIR` is missing or empty;
- `SG_BACKUP_DIR` contains an unresolved `${...}` expression;
- the configured path is not absolute;
- the configured directory does not exist or is not readable and traversable;
- the configured directory is not writable during a real cleanup run;
- `flock` is unavailable.

A `--dry-run` does not require write access to the backup directory.

## Retention policy

Retention is evaluated independently for the two automatic backup families.

### Log Server automatic backups

Recognized form:

~~~text
sgl_v7.4.1.12025_20260915_070000_no_logs_zip
~~~

The script keeps the five most recent distinct SGL backup dates and removes older recognized SGL backup directories.

### Management Server automatic backups

Recognized form:

~~~text
sgm_v7.4.1.12025_20260915_070000.zip
~~~

The script keeps the five most recent distinct SGM backup dates and removes older recognized SGM backup files.

Keeping SGL and SGM retention independent prevents a successful Log Server backup from advancing Management Server retention when the Management Server backup did not complete.

### Manual or commented Management Server backups

Recognized form:

~~~text
sgm_v7.4.1.12025_20260914_091603_Performed before Update Package 2065 activation.zip
~~~

Manual/commented SGM backups are deleted only when both conditions are true:

1. at least five distinct automatic SGM backup dates exist;
2. the manual/commented backup date is older than the oldest of the five retained automatic SGM dates.

If fewer than five automatic SGM dates exist, manual/commented SGM backups are not deleted.

Unrecognized entries, including `sgrollbackfolder`, are ignored.

## Duplicate post-task executions

An SMC backup task can invoke the post-task script more than once when multiple backup targets are configured.

The script uses `flock` to allow only one cleanup instance at a time and waits 60 seconds before evaluating retention. A second overlapping invocation exits without doing anything.

## Installation

Copy the script to the SMC server, for example:

~~~bash
sudo install -o root -g root -m 0755 \
    maintenance/cleanup-smc-backups.sh \
    /usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

Confirm that the account used by SMC can read `SGConfiguration.txt` and can delete entries inside the configured `SG_BACKUP_DIR`.

For an installation where the post-task hook runs as `sgadmin`:

~~~bash
sudo -u sgadmin /usr/local/sbin/forcepoint-backup-cleanup.sh --dry-run --no-wait
~~~

Review the output carefully before enabling deletion.

Then configure **Script to Execute After the Task** with:

~~~text
/usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

No arguments are required for normal scheduled execution.

## Manual testing

Show what would be removed without deleting anything and without waiting 60 seconds:

~~~bash
/usr/local/sbin/forcepoint-backup-cleanup.sh --dry-run --no-wait
~~~

Show command help:

~~~bash
/usr/local/sbin/forcepoint-backup-cleanup.sh --help
~~~

## Logging

The script writes to standard output and also uses the syslog tag:

~~~text
forcepoint-backup-cleanup
~~~

On a system using systemd journal:

~~~bash
journalctl -t forcepoint-backup-cleanup
~~~

## Important limitations

The filename matching is intentionally strict. Files and directories that do not match the documented Forcepoint backup naming forms are not deleted.

If a future Forcepoint SMC release changes backup naming, review and update the matching expressions before relying on cleanup for the new format.
