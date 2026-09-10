## Summary

Describe the change and the operational problem it solves.

## Checklist

- [ ] The change is read-only for scripts distributed in `dist/`.
- [ ] No credentials, keys, PSKs, certificates, customer data or production-specific values are included.
- [ ] Examples use sanitized or documentation-reserved values.
- [ ] `bash -n` passes.
- [ ] ShellCheck has been considered.
- [ ] `./scripts/build-dist.sh --check` passes.
- [ ] Documentation has been updated where needed.
