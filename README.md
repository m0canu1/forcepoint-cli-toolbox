# Forcepoint CLI Toolbox

An unofficial collection of small Bash utilities for inventory, troubleshooting, diagnostics, and narrowly scoped Forcepoint maintenance tasks.

Read-only operational tools live in `dist/`. Scripts that intentionally modify appliance state live separately in `maintenance/` and must provide explicit safeguards and documentation.

## Recommended usage

For production appliances, keep the repository on an admin workstation or jump host and copy only the standalone script you need from `dist/` to the firewall, preferably under `/tmp`.

```bash
scp dist/get-macs.sh admin@fw01:/tmp/
ssh admin@fw01
chmod +x /tmp/get-macs.sh
/tmp/get-macs.sh
rm /tmp/get-macs.sh
```

You do not need to clone the complete repository on the firewall.

When the repository is public and the appliance is allowed outbound HTTPS access, a standalone script can also be downloaded from `raw.githubusercontent.com`. Download and inspect the file before executing it; do not pipe remote content directly into a shell.

## Repository layout

```text
forcepoint-cli-toolbox/
├── dist/                    # Read-only standalone operational scripts
├── maintenance/             # Explicitly mutating maintenance scripts
├── docs/                    # Usage, compatibility and development notes
├── .github/
│   ├── scripts/             # Repository-only CI/safety helpers
│   └── workflows/           # GitHub Actions validation
├── CONTRIBUTING.md
├── SECURITY.md
└── LICENSE
```

## Quick examples

Display MAC and IP information for all interfaces:

```bash
./dist/get-macs.sh
```

Filter by interface name using a Bash regular expression:

```bash
./dist/get-macs.sh '^eth'
./dist/get-macs.sh '^bond'
./dist/get-macs.sh '^(eth0|eth1|bond0)$'
```

Check the kernel routing decision for a documentation-only example destination:

```bash
./dist/check-routing-path.sh 203.0.113.10
./dist/check-routing-path.sh 203.0.113.10 192.0.2.10
```

Inspect the appliance runtime and BusyBox availability:

```bash
./dist/check-runtime.sh
```

## Included tools

| Script | Purpose |
| --- | --- |
| `get-macs.sh` | Physical/logical interface inventory with current/permanent MAC, MAC comparison, IPv4 and IPv6 addresses |
| `get-interface-details.sh` | Interface type, state, carrier, MTU, speed, duplex, master and driver |
| `get-interface-counters.sh` | RX/TX bytes, packets, errors and drops from sysfs |
| `get-routes.sh` | Policy-routing rules, main routing table and referenced routing tables |
| `check-routing-path.sh` | Kernel routing decision for a destination, optionally with a source address |
| `get-neighbors.sh` | IPv4/IPv6 neighbour and ARP information |
| `get-bonds.sh` | Linux bonding configuration and member state |
| `get-vlans.sh` | VLAN interfaces, VLAN IDs, parent links, state and addresses |
| `get-vpn-interfaces.sh` | Interfaces matching common VPN/tunnel naming patterns |
| `get-vpn-routes.sh` | Routes using VPN/tunnel-like interfaces |
| `collect-vpn-diagnostics.sh` | VPN-like interfaces, routes, policy rules, neighbours and available XFRM data |
| `get-system-info.sh` | Kernel, uptime, CPU, memory and filesystem information |
| `get-listening-sockets.sh` | Listening TCP/UDP sockets using `ss` or `netstat` |
| `check-runtime.sh` | Native/BusyBox command availability report |
| `collect-network-diagnostics.sh` | General read-only network troubleshooting snapshot |

## Maintenance tools

Maintenance scripts are intentionally separated from the read-only `dist/` tools. Review them before production use and use any available dry-run mode first.

| Script | Purpose |
| --- | --- |
| `maintenance/cleanup-smc-backups.sh` | Retain the 5 most recent automatic SMC backup dates and remove older automatic/manual SMC backups using `SG_BACKUP_DIR` from `SGConfiguration.txt` |

See [maintenance/README.md](maintenance/README.md) for installation and Forcepoint post-task configuration.

## BusyBox and reduced userspaces

Forcepoint appliances may expose a smaller Linux environment than a general-purpose distribution. BusyBox is commonly present. Scripts should prefer normal commands when available and use BusyBox or `/proc`/`/sys` fallbacks where practical.

Run `dist/check-runtime.sh` on a target appliance to see which commands are native, provided by BusyBox, or unavailable. See [docs/compatibility.md](docs/compatibility.md) for more details.

## Development

`dist/` contains the canonical read-only operational scripts. Explicitly mutating utilities belong in `maintenance/`. Scripts in both locations must remain self-contained and safe to copy individually to an appliance.

CI validates Bash syntax, ShellCheck errors, executable permissions, standalone behavior, and keeps the read-only policy enforced for `dist/`.

See [docs/development.md](docs/development.md).

## Security and privacy

Diagnostic output can contain hostnames, IP addresses, MAC addresses, routes and other environment-specific information. Sanitize output before posting it in public issues or discussions.

Do not commit customer data, credentials, tokens, PSKs, private keys, certificates, packet captures, support bundles or production-specific configuration. See [SECURITY.md](SECURITY.md).

## Safety policy

Scripts in `dist/` are expected to be read-only. They must not change routes, interfaces, firewall policy, VPN configuration, services, kernel parameters or system files. Scripts in `maintenance/` may intentionally modify state, but must be narrowly scoped, documented, and include safety checks appropriate to the operation.

## License

MIT. See [LICENSE](LICENSE).

## Disclaimer

This is an unofficial community/operations toolbox. It is not affiliated with, maintained by, sponsored by, or endorsed by Forcepoint. Product names and trademarks belong to their respective owners.
