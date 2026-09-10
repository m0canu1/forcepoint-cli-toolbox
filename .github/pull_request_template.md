## Summary

Describe the change and the operational problem it solves.

## Checklist

- [ ] The change is read-only for scripts in `dist/`.
- [ ] Every modified or added `dist/*.sh` script is self-contained.
- [ ] No credentials, keys, PSKs, certificates, customer data or production-specific values are included.
- [ ] Examples use sanitized or documentation-reserved values.
- [ ] `bash -n dist/*.sh` passes.
- [ ] ShellCheck has been considered.
- [ ] `bash .github/scripts/check-public-safety.sh` passes.
- [ ] Documentation has been updated where needed.
