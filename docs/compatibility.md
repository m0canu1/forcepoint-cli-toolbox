# Compatibility notes

Forcepoint firewall appliances may expose a reduced Linux userspace. BusyBox is commonly present, so scripts should take advantage of it when practical instead of assuming a full general-purpose distribution.

## Runtime discovery

Start with the standalone runtime checker:

```bash
./dist/check-runtime.sh
```

It reports whether selected commands are available natively, through BusyBox, or are missing.

## Compatibility strategy

For operational scripts, use this order of preference:

1. native command in `PATH`;
2. BusyBox applet when available and compatible with the required options;
3. read-only `/proc` or `/sys` data where practical;
4. a clear `not available` result rather than an unsafe workaround.

BusyBox can list its compiled applets with:

```bash
busybox --list
```

An applet being present does not guarantee support for every GNU option.

## Common commands

Scripts commonly use:

- `bash`
- `ip`
- `awk`
- `cat`
- `date`
- `hostname`

Optional commands include:

- `ethtool` for permanent hardware MAC addresses;
- `ss` or `netstat` for socket inspection;
- `free` for memory summaries;
- `dmesg` for kernel messages;
- `readlink` for driver/master inspection.

Scripts should degrade gracefully when optional commands are unavailable.

## Physical vs logical interfaces

`get-macs.sh` treats an interface as physical when `/sys/class/net/<interface>/device` exists. This is a useful Linux heuristic, but appliance-specific drivers may expose devices differently.

Virtual interfaces commonly include bonds, VLAN subinterfaces, tunnel interfaces and other logical devices. These often do not have a meaningful permanent hardware MAC address.

## Permanent MAC addresses

When `ethtool -P` returns a valid hardware address, `get-macs.sh` compares it with the active address from sysfs. A mismatch is reported as `MATCH=NO`.

For logical interfaces where a permanent address is unavailable or reported as `not set`, the script displays `-`.

## Interface filters

Scripts that support interface filtering accept a Bash regular expression as their first argument.

```bash
./dist/get-macs.sh '^eth'
./dist/get-macs.sh '^bond'
./dist/get-macs.sh '^(eth0|eth1|bond0)$'
```

An omitted filter matches all interface names.

## Reporting compatibility problems

When opening an issue, include the Forcepoint product/version and sanitized `check-runtime.sh` output. Never post customer configuration, credentials, keys, PSKs, internal hostnames or unsanitized diagnostic output.
