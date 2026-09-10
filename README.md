# Forcepoint CLI Toolbox

An unofficial collection of small, read-only Bash utilities for inventory, troubleshooting, and diagnostics on Forcepoint firewalls and their underlying Linux environment.

The repository is intentionally conservative: scripts should prefer inspection over configuration changes, avoid destructive commands, and work with the standard tools commonly available on firewall appliances.

## Repository layout

```text
forcepoint-cli-toolbox/
├── .github/workflows/       # CI checks
├── docs/                    # Usage and compatibility notes
├── scripts/
│   ├── network/             # Interfaces, MAC/IP, routes, neighbours, bonding
│   ├── system/              # Host/system information
│   └── troubleshooting/     # Read-only diagnostic collectors
├── CONTRIBUTING.md
└── README.md
```

## Quick start

Clone the repository and make the scripts executable:

```bash
git clone https://github.com/m0canu1/forcepoint-cli-toolbox.git
cd forcepoint-cli-toolbox
chmod +x scripts/**/*.sh
```

Example: display MAC and IP information for every interface:

```bash
./scripts/network/get-macs.sh
```

Filter interfaces by Bash regular expression:

```bash
./scripts/network/get-macs.sh '^eth'
./scripts/network/get-macs.sh '^bond'
./scripts/network/get-macs.sh '^(eth0|eth1|bond0)$'
```

## Included tools

| Script | Purpose |
| --- | --- |
| `scripts/network/get-macs.sh` | Physical/logical interface inventory with current MAC, permanent MAC, MAC comparison, IPv4 and IPv6 addresses |
| `scripts/network/get-routes.sh` | Dump policy-routing rules and the routing tables referenced by them |
| `scripts/network/get-neighbors.sh` | Display IPv4/IPv6 neighbour and ARP information |
| `scripts/network/get-bonds.sh` | Display Linux bonding configuration and member state |
| `scripts/system/get-system-info.sh` | Collect basic host, kernel, uptime, CPU, memory and filesystem information |
| `scripts/troubleshooting/collect-network-diagnostics.sh` | Produce a read-only network troubleshooting snapshot |

## Compatibility

The scripts target Bash on Linux. They deliberately avoid uncommon dependencies where practical.

Common commands used include:

- `ip`
- `awk`
- `date`
- `hostname`
- `cat`

Some information is optional and is displayed only when the corresponding utility exists, for example `ethtool` or `ss`.

The exact Linux userspace available on Forcepoint appliances can differ by product and release. Test scripts on a non-production appliance or during an appropriate maintenance window before relying on them operationally.

## Safety policy

Scripts committed to this repository should be read-only by default. They must not change routes, interfaces, firewall policy, VPN configuration, services, kernel parameters, or system files unless the behavior is explicitly documented and intentionally placed in a separate configuration-oriented area in the future.

## Disclaimer

This is an unofficial community/operations toolbox. It is not affiliated with, maintained by, or endorsed by Forcepoint.
