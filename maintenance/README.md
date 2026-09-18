# Maintenance scripts

This directory contains operational scripts that can intentionally modify or delete data.

Unlike the diagnostic scripts in `dist/`, maintenance scripts are not read-only. Review the script and its documentation before use, test with any available dry-run mode, and confirm the target paths and permissions on the appliance or SMC server.

## Included tools

| Script | Purpose |
| --- | --- |
| `forcepoint-backup-cleanup.sh` | Apply retention to Management Server backups from `SG_BACKUP_DIR` (or the default `${SG_DATA_ROOT_DIR}/backups` when absent) and Log Server backups from `LOG_BACKUP_DIR` |

## Forcepoint backup cleanup quick start

Install the script on the SMC server:

~~~bash
sudo install -o root -g root -m 0755 \
    maintenance/forcepoint-backup-cleanup.sh \
    /usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

Test it as the SMC post-task account, commonly `sgadmin`:

~~~bash
sudo -u sgadmin /usr/local/sbin/forcepoint-backup-cleanup.sh \
    --dry-run --no-wait
~~~

After reviewing the dry-run output, edit the SMC backup task and set **Script to Execute After the Task** to:

~~~text
/usr/local/sbin/forcepoint-backup-cleanup.sh
~~~

The script automatically discovers both backup locations:

~~~text
/usr/local/forcepoint/smc/data/SGConfiguration.txt
  -> SG_BACKUP_DIR, or ${SG_DATA_ROOT_DIR}/backups when the key is absent

/usr/local/forcepoint/smc/data/LogServerConfiguration.txt
  -> LOG_BACKUP_DIR
~~~

A value such as `LOG_BACKUP_DIR=${SG_DATA_ROOT_DIR}/backups` is safely resolved to the SMC installation root without sourcing the configuration file.

For the complete installation procedure, execution-account check, retention behavior, SMC task configuration, logging, troubleshooting, and rollback instructions, see [Forcepoint backup cleanup](../docs/forcepoint-backup-cleanup.md).
