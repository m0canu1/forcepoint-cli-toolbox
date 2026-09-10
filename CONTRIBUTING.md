# Contributing

Contributions should keep the toolbox predictable, portable and safe for operational use.

## Core principles

- Prefer read-only inspection commands.
- Do not change firewall, routing, VPN, interface, service, kernel or system configuration from scripts in `dist/`.
- Keep runtime dependencies small and detect optional commands before using them.
- Assume some Forcepoint appliances expose a reduced Linux userspace.
- Prefer native commands when present and use BusyBox or `/proc`/`/sys` fallbacks where practical.
- Avoid GNU-only options when a portable alternative exists.
- Print hostname and timestamp in diagnostic reports when useful.
- Quote shell variables and keep scripts compatible with Bash.
- Never commit credentials, tokens, keys, PSKs, certificates, packet captures, support bundles, customer data, internal addressing plans or production-specific values.

## Canonical script location

All operational scripts live directly under `dist/`.

Edit `dist/*.sh` directly. There is no generated copy and no separate source tree.

Every script in `dist/` must be self-contained so it can be copied individually to a firewall and executed without any other repository file.

## Naming

Use lowercase descriptive filenames such as:

```text
get-routes.sh
get-interface-counters.sh
collect-network-diagnostics.sh
```

## Validation

Before committing:

```bash
for script in dist/*.sh; do
    bash -n "$script"
done

bash .github/scripts/check-public-safety.sh
```

If ShellCheck is available:

```bash
shellcheck -S error dist/*.sh
```

GitHub Actions runs the same classes of checks automatically.

## Documentation

Document purpose, arguments, limitations and example usage. Examples must use sanitized or documentation-reserved values rather than customer or production information.

When reporting appliance compatibility, include the Forcepoint product/version and sanitized output from `dist/check-runtime.sh` when possible.
