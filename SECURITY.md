# Security policy

## Reporting a security issue

Please use GitHub's private vulnerability reporting / Security Advisory mechanism when it is available for this repository.

Do not include credentials, private keys, tokens, PSKs, customer data, production configuration, packet captures, support bundles, internal hostnames or non-public addressing details in a public issue.

If private reporting is unavailable, open a minimal issue asking the maintainer for a private contact method without including the sensitive details themselves.

## Operational safety

The scripts in `dist/` are intended to be read-only diagnostic tools. Review a script before running it on a production appliance, especially after downloading it from the network.

Prefer copying scripts from a trusted admin workstation to `/tmp`, running them, collecting the required output, and removing them when finished.

## Diagnostic output

Outputs may contain operationally sensitive information such as:

- hostnames;
- interface names;
- MAC addresses;
- IP addresses and prefixes;
- routes and next hops;
- neighbour/ARP entries;
- socket information;
- VPN/tunnel metadata.

Sanitize diagnostic output before sharing it publicly.
