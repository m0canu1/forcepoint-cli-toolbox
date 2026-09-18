# Contributing

Contributions should keep the toolbox predictable, portable and safe for operational use.

## Core principles

- Prefer read-only inspection commands for diagnostic tooling.
- Do not change firewall, routing, VPN, interface, service, kernel or system configuration from scripts in `dist/`.
- Put intentionally mutating or destructive operational utilities in `maintenance/`, not `dist/`.
- Maintenance scripts must validate their target paths, document their effects and provide a dry-run or equivalent preview mode when practical.
- Keep runtime dependencies small and detect optional commands before using them.
- Assume some Forcepoint appliances expose a reduced Linux userspace.
- Prefer native commands when present and use BusyBox or `/proc`/`/sys` fallbacks where practical.
- Avoid GNU-only options when a portable alternative exists.
- Print hostname and timestamp in diagnostic reports when useful.
- Quote shell variables and keep scripts compatible with Bash.
- Never commit credentials, tokens, keys, PSKs, certificates, packet captures, support bundles, customer data, internal addressing plans or production-specific values.

## Script locations

Read-only diagnostic scripts live directly under `dist/`.

Maintenance scripts that intentionally modify or delete data live under `maintenance/`.

There is no generated copy and no separate source tree. Every operational script must remain self-contained so it can be copied individually to a target Forcepoint system and executed without any other repository file.

## Naming

Use lowercase descriptive filenames such as:

```text
get-routes.sh
get-interface-counters.sh
collect-network-diagnostics.sh
cleanup-smc-backups.sh
```

## Validation

Before committing:

```bash
for script in dist/*.sh maintenance/*.sh; do
    [ -f "$script" ] || continue
    bash -n "$script"
done

bash .github/scripts/check-public-safety.sh
```

If ShellCheck is available:

```bash
shellcheck -S error dist/*.sh maintenance/*.sh
```

GitHub Actions runs the same classes of checks automatically.

The public-safety mutation scan intentionally applies to `dist/`; scripts in `maintenance/` are reviewed as explicitly mutating tools instead.

## Documentation

Document purpose, arguments, limitations and example usage. Examples must use sanitized or documentation-reserved values rather than customer or production information.

For maintenance scripts, also document what can be modified or deleted, how target paths are discovered or validated, and how to perform a non-destructive test.

When reporting appliance compatibility, include the Forcepoint product/version and sanitized output from `dist/check-runtime.sh` when possible.
