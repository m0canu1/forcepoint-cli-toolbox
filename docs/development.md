# Development

## Design goals

The toolbox is designed for operational diagnostics on firewall appliances rather than as a general Linux administration framework.

New scripts should be:

- read-only by default, with state-changing utilities isolated under `maintenance/`;
- understandable without hidden state;
- conservative about dependencies;
- useful when copied as a single file;
- tolerant of reduced appliance userspaces;
- explicit when information cannot be collected.

## Canonical source

`dist/` is the source of truth for read-only operational scripts. `maintenance/` contains explicitly state-changing utilities.

There is no generated distribution layer and no separate source directory. Edit scripts directly in the appropriate directory.

Every script must remain self-contained at runtime and must not source another repository file. Maintenance scripts must be narrowly scoped and should expose a dry-run path when practical.

## BusyBox

BusyBox is commonly available on reduced firewall Linux environments, but the exact applet set and supported options can vary by version.

Where practical:

1. prefer a normal command already available in `PATH`;
2. fall back to a BusyBox applet if the standalone command is absent;
3. prefer `/proc` or `/sys` for simple read-only kernel data;
4. fail gracefully when the requested information cannot be obtained.

Do not assume a BusyBox applet supports every GNU option.

## Tests

CI performs:

- Bash syntax validation for `dist/*.sh` and `maintenance/*.sh`;
- ShellCheck at error severity;
- executable-permission checks;
- standalone-script checks;
- a public-safety scan for obvious secrets and sensitive file types;
- enforcement that `dist/` remains read-only.

Run the same checks locally before opening a pull request:

```bash
for script in dist/*.sh maintenance/*.sh; do
    [ -f "$script" ] || continue
    bash -n "$script"
done

shellcheck -S error dist/*.sh maintenance/*.sh
bash .github/scripts/check-public-safety.sh
```

## Example data

Use IETF documentation ranges such as `192.0.2.0/24`, `198.51.100.0/24` and `203.0.113.0/24` in examples. Do not copy real customer addressing, hostnames or configuration into documentation or tests.
