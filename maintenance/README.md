# Maintenance scripts

This directory contains operational scripts that can intentionally modify or delete data.

Unlike the diagnostic scripts in `dist/`, maintenance scripts are not read-only. Review the script and its documentation before use, test with any available dry-run mode, and confirm the target paths and permissions on the appliance or SMC server.

## Included tools

| Script | Purpose |
| --- | --- |
| `cleanup-smc-backups.sh` | Apply retention to Forcepoint SMC backup files and directories using `SG_BACKUP_DIR` from `SGConfiguration.txt` |

## SMC backup cleanup quick start

Install the script on the SMC server:

~~~bash
sudo install -o root -g root -m 0755     maintenance/cleanup-smc-backups.sh     /usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

Test it as the SMC post-task account, commonly `sgadmin`:

~~~bash
sudo -u sgadmin /usr/local/sbin/forcepoint-backup-cleanup.sh     --dry-run --no-wait
~~~

After reviewing the dry-run output, edit the SMC backup task and set **Script to Execute After the Task** to:

~~~text
/usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

The script automatically reads the backup path from:

~~~text
/usr/local/forcepoint/smc/data/SGConfiguration.txt
~~~

using its `SG_BACKUP_DIR` property.

For the complete installation procedure, execution-account check, retention behavior, SMC task configuration, logging, and rollback instructions, see [SMC backup cleanup](../docs/smc-backup-cleanup.md).
