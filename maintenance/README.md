# Maintenance scripts

This directory contains operational scripts that can intentionally modify or delete data.

Unlike the diagnostic scripts in `dist/`, maintenance scripts are not read-only. Review the script and its documentation before use, test with any available dry-run mode, and confirm the target paths and permissions on the appliance or SMC server.

## Included tools

| Script | Purpose |
| --- | --- |
| `cleanup-smc-backups.sh` | Apply retention to Forcepoint SMC backup files and directories using `SG_BACKUP_DIR` from `SGConfiguration.txt` |

See [SMC backup cleanup](../docs/smc-backup-cleanup.md) for installation, retention behavior, and testing.
