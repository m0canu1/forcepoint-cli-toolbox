# Usage

## Recommended production workflow

Keep the repository on an admin workstation or jump host. Copy only the required standalone script from `dist/` to the firewall.

```bash
scp dist/get-macs.sh admin@fw01:/tmp/
ssh admin@fw01
chmod +x /tmp/get-macs.sh
/tmp/get-macs.sh
rm /tmp/get-macs.sh
```

This avoids leaving a Git checkout or unnecessary tooling on the appliance.

## Runtime check

Before using more advanced scripts on an unfamiliar appliance, run:

```bash
./dist/check-runtime.sh
```

It reports whether common commands are available as native binaries, BusyBox applets, or not at all.

## Interface filters

Several scripts accept a Bash regular expression as their first argument.

```bash
./dist/get-macs.sh '^eth'
./dist/get-macs.sh '^bond'
./dist/get-macs.sh '^(eth0|eth1|bond0)$'
```

## Routing-path lookup

Use a destination address to ask the Linux kernel which route it would select:

```bash
./dist/check-routing-path.sh 203.0.113.10
```

Optionally specify a source address:

```bash
./dist/check-routing-path.sh 203.0.113.10 192.0.2.10
```

The addresses above are documentation examples, not production values.

## Direct download

When the repository is public and outbound HTTPS from the appliance is explicitly permitted, a file may be downloaded from `raw.githubusercontent.com` with `curl`, `wget`, or an available BusyBox applet.

Prefer this pattern:

```bash
wget -O /tmp/get-macs.sh https://raw.githubusercontent.com/m0canu1/forcepoint-cli-toolbox/main/dist/get-macs.sh
less /tmp/get-macs.sh
chmod +x /tmp/get-macs.sh
/tmp/get-macs.sh
```

Do not use `curl ... | bash` or equivalent patterns on production infrastructure.

## Sharing output

Treat output as potentially sensitive. Remove or replace customer identifiers, public and private IP addresses, hostnames, MAC addresses, tunnel details and routing information before posting output publicly.
