# Development

## Design goals

The toolbox is designed for operational work on Forcepoint systems rather than as a general Linux administration framework.

Diagnostic scripts should be:

- read-only;
- understandable without hidden state;
- conservative about dependencies;
- useful when copied as a single file;
- tolerant of reduced appliance userspaces;
- explicit when information cannot be collected.

Maintenance scripts may intentionally modify or delete data, but should be:

- narrowly scoped to the documented maintenance task;
- defensive about path discovery and validation;
- explicit in their logs;
- safe against duplicate/concurrent execution when relevant;
- testable without changes through a dry-run or equivalent mode when practical.

## Canonical source

`dist/` is the source of truth for read-only diagnostic scripts.

`maintenance/` is the source of truth for explicitly mutating operational scripts.

There is no generated distribution layer and no separate source directory. Edit the script in its operational directory directly.

Every script must remain self-contained at runtime and must not source another repository file.

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
- ShellCheck at error severity for both script groups;
- executable-permission checks for `dist/*.sh`;
- standalone-script checks for `dist/*.sh`;
- a public-safety scan for obvious secrets, sensitive file types and mutating commands in `dist/`.

Run the same checks locally before opening a pull request:

```bash
for script in dist/*.sh maintenance/*.sh; do
    [ -f "$script" ] || continue
    bash -n "$script"
done

shellcheck -S error dist/*.sh maintenance/*.sh
bash .github/scripts/check-public-safety.sh
```

For maintenance scripts, also exercise the dry-run path against representative sanitized test data before enabling destructive execution.

## Example data

Use IETF documentation ranges such as `192.0.2.0/24`, `198.51.100.0/24` and `203.0.113.0/24` in examples. Do not copy real customer addressing, hostnames or configuration into documentation or tests.
