# Tools

All six tools share the [common interface](usage.md). Defaults below apply when `-r` is not given.

## fping-sweep

ICMP ping sweep. Fastest for simple "is it alive?" checks. Auto-splits large CIDRs into /17 chunks to stay within fping's 131K address limit.

```bash
docker run --rm host-discovery fping-sweep 10.0.0.0/16
docker run --rm host-discovery fping-sweep -r 5000 10.0.0.0/16
```

**Tuning:** `-r 0` (no retries), `-t 100` (100ms timeout), `-B 1` (no backoff), `-i 1` (1ms interval). Rate flag adjusts interval via `1000/rate`.

## nmap-discover

Multi-protocol discovery. Catches hosts that block ICMP by probing with TCP SYN/ACK and UDP.

```bash
docker run --rm host-discovery nmap-discover 192.168.0.0/16
```

**Probes:** ICMP echo + timestamp, TCP SYN (22,80,443,8080), TCP ACK (80,443), UDP (40125).

**Tuning:** `-n` (skip DNS), `--min-rate 5000`, `--max-retries 1`, `--max-rtt-timeout 200ms`.

## zmap-sweep

Raw-socket line-rate scanning. Requires `--privileged` for raw sockets.

```bash
docker run --rm --privileged host-discovery zmap-sweep 10.0.0.0/8
```

**Tuning:** 100K pps default, 4s cooldown, IP-layer mode (`-X`). Overrides the default zmap blocklist to allow RFC1918 ranges.

## masscan-sweep

High-speed TCP SYN + ICMP discovery. Bridges the gap between zmap (ICMP-only, raw speed) and nmap (thorough but slower) — probes multiple TCP ports alongside ICMP using masscan's async TCP/IP stack. Requires `--privileged` for raw sockets.

```bash
docker run --rm --privileged host-discovery masscan-sweep 10.0.0.0/8
```

**Probes:** TCP SYN (80,443,22,8080,8443,3389,445) + ICMP echo.

**Tuning:** 10K pps default (conservative for 8 probes/host), 2s cooldown, open-only output. Rate flag (`-r`) adjusts pps directly.

## arp-scan-sweep

L2 ARP discovery. Finds every host on a local subnet regardless of firewall rules — ARP is required for IP communication, so it can't be blocked. The most reliable method for directly-connected subnets.

**Requires `--net=host --privileged`** — must be on the host's L2 network to send/receive ARP frames.

```bash
docker run --rm --net=host --privileged host-discovery arp-scan-sweep 192.168.1.0/24
docker run --rm --net=host --privileged host-discovery arp-scan-sweep --local
```

**Tuning:** 1 retry, 200ms timeout, 1ms interval. Rate flag adjusts interval via `1000/rate`.

**Limitation:** Only discovers hosts on directly-connected L2 subnets. Cannot scan across routers.

## nbtscan-sweep

NetBIOS name scan (UDP port 137). Discovers Windows and Samba hosts that advertise NetBIOS names — catches machines in Windows-heavy environments even when ICMP is blocked.

```bash
docker run --rm host-discovery nbtscan-sweep 192.168.0.0/16
```

**Tuning:** 1s response timeout. nbtscan has no pps knob, so `-r` is mapped to its `-b` bandwidth throttle (50-byte query × 8 bits × rate).

**Limitation:** Only discovers hosts running NetBIOS/SMB services. Silent against Linux, macOS, and network devices unless they run Samba.

## Container Contents

The image includes all dependencies:

- fping
- nmap
- zmap
- masscan
- arp-scan
- nbtscan
- libpcap-dev (runtime dependency for masscan)
- bash
- iproute2-minimal (for `--local` subnet detection)
