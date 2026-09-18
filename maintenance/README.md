# Maintenance scripts

Scripts in this directory intentionally modify Forcepoint appliance state. Review them before production use.

## cleanup-smc-backups.sh

Cleans Forcepoint SMC backups according to the SMC-configured backup directory.

The script reads:

```text
/usr/local/forcepoint/smc/data/SGConfiguration.txt
```

and extracts the exact `SG_BACKUP_DIR` property. It does not source or execute the configuration file.

### Retention policy

The script:

- keeps the 5 most recent distinct dates that contain recognized automatic backups;
- deletes automatic Log Server and Management Server backups from older dates;
- uses the oldest of those 5 retained dates as the cutoff for manual/commented Management Server backups;
- deletes manual/commented Management Server backups only when their embedded date is older than that cutoff;
- ignores unrecognized files and directories, including `sgrollbackfolder`;
- performs no deletion if fewer than 5 distinct automatic backup dates exist.

Recognized automatic names:

```text
sgl_<version>_YYYYMMDD_HHMMSS_no_logs_zip
sgm_<version>_YYYYMMDD_HHMMSS.zip
```

Recognized manual/commented Management Server names:

```text
sgm_<version>_YYYYMMDD_HHMMSS_<description>.zip
```

### Install on the SMC

Copy the script to the SMC and install it with executable permissions:

```bash
sudo install -o root -g root -m 0755 maintenance/cleanup-smc-backups.sh \
  /usr/local/sbin/forcepoint-smc-backup-cleanup.sh
```

The Forcepoint post-task process must be able to read `SGConfiguration.txt` and read/write the configured `SG_BACKUP_DIR`. In observed SMC installations, post-task scripts can run as `sgadmin`; verify this in your environment.

### Test first

Run a non-destructive test as the same account used by the Forcepoint post-task process:

```bash
sudo -u sgadmin /usr/local/sbin/forcepoint-smc-backup-cleanup.sh --dry-run --no-wait
```

Review the `KEEP` and `WOULD DELETE` lines before enabling automatic execution.

### Configure the Forcepoint backup task

Set **Script to Execute After the Task** to:

```text
/usr/local/sbin/forcepoint-smc-backup-cleanup.sh
```

No arguments are required. Normal execution performs cleanup.

The script waits 60 seconds before cleanup and uses `flock` to avoid concurrent executions when Forcepoint invokes the post-task script more than once for a multi-target backup task.

### Logging

Output is written to stdout and, when `logger` is available, to the system journal/syslog with tag:

```text
forcepoint-smc-backup-cleanup
```

For example:

```bash
journalctl -t forcepoint-smc-backup-cleanup
```

### Safety notes

- `SG_BACKUP_DIR` must resolve to an absolute path and cannot be `/`.
- Configuration values containing unresolved `${...}` expressions are rejected rather than evaluated.
- Only recognized Forcepoint backup names are eligible for deletion.
- The configuration file is parsed as data and is never sourced.
