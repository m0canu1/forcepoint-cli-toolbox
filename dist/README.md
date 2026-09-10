# Standalone distribution

Files in this directory are intended to be copied individually to a Forcepoint firewall and executed without cloning the complete repository.

## Recommended workflow

```text
GitHub repository
      |
      v
Admin workstation / jump host
      |
      |  scp one script
      v
Forcepoint firewall /tmp
      |
      |  execute
      v
remove when finished
```

Example:

```bash
scp dist/get-macs.sh admin@fw01:/tmp/
ssh admin@fw01
chmod +x /tmp/get-macs.sh
/tmp/get-macs.sh
rm /tmp/get-macs.sh
```

## Policy

A script belongs in `dist/` only when it is self-contained at runtime. Distribution scripts must not source files elsewhere in the repository.

They should:

- remain read-only;
- prefer native Linux utilities;
- use BusyBox fallbacks where practical;
- use `/proc` and `/sys` when that improves portability;
- degrade gracefully when optional commands are unavailable;
- avoid GNU-specific assumptions where BusyBox compatibility matters.

`dist/` is generated from source scripts under `scripts/`; do not edit deployment copies directly.

## Direct downloads

When the repository is public and outbound HTTPS is allowed, standalone scripts may be downloaded from `raw.githubusercontent.com`. Review the downloaded file before executing it and do not pipe remote content directly into a shell.
