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

## Source and distribution

Maintain source scripts under:

- `scripts/network/`
- `scripts/vpn/`
- `scripts/system/`
- `scripts/troubleshooting/`

Do not edit generated standalone scripts in `dist/` directly. After changing a source script, run:

```bash
./scripts/build-dist.sh
```

Then verify that distribution files are synchronized:

```bash
./scripts/build-dist.sh --check
```

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
find scripts dist -type f -name '*.sh' -exec bash -n {} \;
./scripts/build-dist.sh --check
./scripts/ci/check-public-safety.sh
```

If ShellCheck is available:

```bash
find scripts dist -type f -name '*.sh' -print0 | xargs -0 shellcheck -S error
```

## Documentation

Document purpose, arguments, limitations and example usage. Examples must use sanitized or documentation-reserved values rather than customer or production information.

When reporting appliance compatibility, include the Forcepoint product/version and sanitized output from `dist/check-runtime.sh` when possible.
