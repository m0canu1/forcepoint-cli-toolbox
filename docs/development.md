# Development

## Design goals

The toolbox is designed for operational diagnostics on firewall appliances rather than as a general Linux administration framework.

New scripts should be:

- read-only by default;
- understandable without hidden state;
- conservative about dependencies;
- useful when copied as a single file;
- tolerant of reduced appliance userspaces;
- explicit when information cannot be collected.

## Source vs distribution

Source files live under `scripts/`. Standalone deployment copies live in `dist/`.

`dist/` is generated from a fixed manifest by:

```bash
./scripts/build-dist.sh
```

Check that committed distribution files match the source:

```bash
./scripts/build-dist.sh --check
```

Every script listed in the distribution manifest must be self-contained at runtime. It must not source another repository file.

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

- Bash syntax validation;
- ShellCheck at error severity;
- `dist/` synchronization checks;
- a public-safety scan for obvious secrets, sensitive file types and mutating commands in `dist/`.

Run the same checks locally before opening a pull request.

## Example data

Use IETF documentation ranges such as `192.0.2.0/24`, `198.51.100.0/24` and `203.0.113.0/24` in examples. Do not copy real customer addressing, hostnames or configuration into documentation or tests.
