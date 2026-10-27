# Docker Host Discovery

Fast RFC1918 host discovery tools in a minimal Alpine container. Wraps fping, nmap, zmap, masscan, arp-scan, and nbtscan with tuned defaults for LAN scanning.

## Quick Start

```bash
docker build -t host-discovery .
docker run --rm --privileged host-discovery fping-sweep 192.168.1.0/24
```

> **Only scan networks you own or are authorized to test.** These tools send high-rate probes and will trip IDS/IPS alerts.

## Tools

### fping-sweep

ICMP ping sweep. Fastest for simple "is it alive?" checks. Auto-splits large CIDRs into /17 chunks to stay within fping's 131K address limit.

```bash
docker run --rm host-discovery fping-sweep 10.0.0.0/16
docker run --rm host-discovery fping-sweep -r 5000 10.0.0.0/16
```

**Tuning:** `-r 0` (no retries), `-t 100` (100ms timeout), `-B 1` (no backoff), `-i 1` (1ms interval). Rate flag adjusts interval via `1000/rate`.

### nmap-discover

Multi-protocol discovery. Catches hosts that block ICMP by probing with TCP SYN/ACK and UDP.

```bash
docker run --rm host-discovery nmap-discover 192.168.0.0/16
```

**Probes:** ICMP echo + timestamp, TCP SYN (22,80,443,8080), TCP ACK (80,443), UDP (40125).

**Tuning:** `-n` (skip DNS), `--min-rate 5000`, `--max-retries 1`, `--max-rtt-timeout 200ms`.

### zmap-sweep

Raw-socket line-rate scanning. Requires `--privileged` for raw sockets.

```bash
docker run --rm --privileged host-discovery zmap-sweep 10.0.0.0/8
```

**Tuning:** 100K pps default, 4s cooldown, IP-layer mode (`-X`). Overrides the default zmap blocklist to allow RFC1918 ranges.

### masscan-sweep

High-speed TCP SYN + ICMP discovery. Bridges the gap between zmap (ICMP-only, raw speed) and nmap (thorough but slower) — probes multiple TCP ports alongside ICMP using masscan's async TCP/IP stack. Requires `--privileged` for raw sockets.

```bash
docker run --rm --privileged host-discovery masscan-sweep 10.0.0.0/8
```

**Probes:** TCP SYN (80,443,22,8080,8443,3389,445) + ICMP echo.

**Tuning:** 10K pps default (conservative for 8 probes/host), 2s cooldown, open-only output. Rate flag (`-r`) adjusts pps directly.

### arp-scan-sweep

L2 ARP discovery. Finds every host on a local subnet regardless of firewall rules — ARP is required for IP communication, so it can't be blocked. The most reliable method for directly-connected subnets.

**Requires `--net=host --privileged`** — must be on the host's L2 network to send/receive ARP frames.

```bash
docker run --rm --net=host --privileged host-discovery arp-scan-sweep 192.168.1.0/24
docker run --rm --net=host --privileged host-discovery arp-scan-sweep --local
```

**Tuning:** 1 retry, 200ms timeout, 1ms interval. Rate flag adjusts interval via `1000/rate`.

**Limitation:** Only discovers hosts on directly-connected L2 subnets. Cannot scan across routers.

### nbtscan-sweep

NetBIOS name scan (UDP port 137). Discovers Windows and Samba hosts that advertise NetBIOS names — catches machines in Windows-heavy environments even when ICMP is blocked.

```bash
docker run --rm host-discovery nbtscan-sweep 192.168.0.0/16
```

**Tuning:** 1s response timeout. nbtscan has no pps knob, so `-r` is mapped to its `-b` bandwidth throttle (50-byte query × 8 bits × rate).

**Limitation:** Only discovers hosts running NetBIOS/SMB services. Silent against Linux, macOS, and network devices unless they run Samba.

## Common Interface

All six tools share the same CLI:

```
Usage: <tool> [OPTIONS] [CIDR...]

  -f, --file FILE    Read targets from file (one CIDR/line)
  -r, --rate NUM     Packets per second (tool-specific default)
  -l, --local        Auto-detect local RFC1918 subnets
  -o, --output FILE  Write results to file (default: stdout)
  -h, --help         Show usage
```

**Output:** One alive IP per line, numerically sorted, on stdout. Progress and warnings go to stderr.

Targets may be CIDRs or bare IPv4 addresses (treated as `/32`); anything else is rejected.

If no targets are specified, all tools default to scanning the full RFC1918 space via `rfc1918.conf`. `--local` exits with an error if no RFC1918 subnets are found, rather than falling back to the full space.

### Saving Results

Results go to stdout and progress to stderr, so standard redirection works:

```bash
# Save to file
docker run --rm host-discovery fping-sweep 10.0.0.0/24 > alive.txt

# Pipe to another tool
docker run --rm host-discovery fping-sweep 10.0.0.0/24 | wc -l

# Use the built-in -o flag (needs a bind mount)
docker run --rm -v "$PWD":/output host-discovery fping-sweep 10.0.0.0/24 -o /output/alive.txt
```

## Comparison

| Tool | Speed | Coverage | Privileges | Network Mode |
|------|-------|----------|------------|--------------|
| fping-sweep | Fast | ICMP only | No | NAT bridge |
| nmap-discover | Moderate | ICMP + TCP + UDP | No* | NAT bridge |
| zmap-sweep | Fastest | ICMP only | `--privileged` | NAT bridge |
| masscan-sweep | Fast | ICMP + TCP | `--privileged` | NAT bridge |
| arp-scan-sweep | Fast | ARP (L2) | `--privileged` | `--net=host` |
| nbtscan-sweep | Fast | NetBIOS (UDP 137) | No | NAT bridge |

*nmap runs unprivileged but some probe types may be limited without root.

### Worst-Case Runtimes

Theoretical scan times when zero hosts respond — every probe hits its timeout. Default rates, no `-r` override.

Runtime ≈ `(probes_per_host × addresses) / rate + cooldown`

| Tool | Probes/Host | Rate (pps) | Cooldown | /24 (256) | /16 (65K) | RFC1918 (17.9M) |
|------|-------------|------------|----------|-----------|-----------|-----------------|
| fping-sweep | 1 | 1,000 | 100ms | <1s | 1m 6s | 4h 58m |
| nmap-discover | 18 | 5,000 | 200ms | ~1s | ~4m | ~17.9h |
| zmap-sweep | 1 | 100,000 | 4s | ~4s | ~5s | ~3m |
| masscan-sweep | 8 | 10,000 | 2s | ~2s | ~54s | ~4h |
| arp-scan-sweep | 2 | 1,000 | 200ms | ~1s | ~2m 11s | ~10h |
| nbtscan-sweep | 1 | unthrottled | 1s | ~1s | link-bound | link-bound |

**nmap-discover:** 18 = 9 probe types × 2 (max-retries 1). Large scans pipeline across hostgroups so timeout overhead is amortized.
**arp-scan-sweep:** 2 = initial + 1 retry. L2-only — cannot cross routers; RFC1918 is theoretical.
**nbtscan-sweep:** Sends queries as fast as the link allows unless `-r` is set, then waits 1s for replies. Large ranges can drop queries on slow links; set `-r` to throttle.

## Networking: NAT Bridge vs Host Mode

By default the examples use Docker's NAT bridge network (no `--net=host`). This is deliberate.

zmap and masscan craft raw Ethernet frames and address them all to a single gateway MAC — they never ARP individual hosts. With `--net=host` the container shares the host's network namespace, so targets on directly-connected subnets are on the same L2 segment. zmap/masscan send probes to the gateway MAC and the router typically won't hairpin traffic back to the same interface, so only the gateway itself is discovered.

With the default NAT bridge, every target is behind the Docker bridge gateway (`172.17.0.1`), which is the host kernel. The host kernel routes and NATs the raw packets out the physical interface using its own ARP cache, so all hosts are reachable regardless of which tool is used.

**Trade-off:** `--local` detects subnets from inside the container's network namespace. Under NAT bridge that means the Docker bridge subnet (`172.17.0.0/16`), not the host's physical LANs. Pass target CIDRs explicitly instead, or detect them on the host first:

```bash
# Detect host subnets, then pass them in
SUBNETS=$(ip -4 route show scope link | awk '{print $1}' | grep -E '^(10\.|172\.1[6-9]\.|172\.2[0-9]\.|172\.3[01]\.|192\.168\.)')
docker run --rm --privileged host-discovery zmap-sweep $SUBNETS
```

If you do need `--local` to work (and only use fping/nmap/nbtscan), `--net=host` is fine:

```bash
docker run --rm --net=host host-discovery fping-sweep --local
docker run --rm --net=host host-discovery nmap-discover --local
docker run --rm --net=host host-discovery nbtscan-sweep --local
```

**Exception — arp-scan-sweep:** ARP is L2-only, so arp-scan *always* needs `--net=host` to reach the host's physical LAN. It's the one tool where NAT bridge cannot work — ARP frames don't cross L3 boundaries.

## Requirements

The container includes all dependencies:

- fping
- nmap
- zmap
- masscan
- arp-scan
- nbtscan
- libpcap-dev (runtime dependency for masscan)
- bash
- iproute2-minimal (for `--local` subnet detection)

## License

Copyright (C) 2026 Nic Boet

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See [LICENSE](LICENSE).

The container image bundles third-party tools (nmap, masscan, zmap, fping, arp-scan, nbtscan) installed from Alpine packages; each remains under its own license.
