# Docker Host Discovery

Fast RFC1918 host discovery tools in a minimal Alpine container. Wraps fping, nmap, zmap, masscan, arp-scan, and nbtscan with tuned defaults for LAN scanning.

> **Only scan networks you own or are authorized to test.** These tools send high-rate probes and will trip IDS/IPS alerts.

## Quick Start

```bash
docker build -t host-discovery .
docker run --rm --privileged host-discovery fping-sweep 192.168.1.0/24
```

## Recommended for Large Networks

For reliable yet fast discovery across an enterprise, use **`masscan-sweep`** with a raised rate and a target file scoped to your allocated ranges:

```bash
docker run --rm --privileged -v "$PWD":/work host-discovery \
    masscan-sweep -r 100000 -f /work/targets.txt > alive.txt
```

ICMP plus TCP SYN on common ports catches hosts that drop ping, while staying stateless and fast — the full RFC1918 space in ~24 minutes at 100K pps. See [performance](docs/performance.md) for the reasoning and complementary tools.

## Tools

| Tool | Method | Best for |
|------|--------|----------|
| `fping-sweep` | ICMP | Quick "is it alive?" on small ranges |
| `nmap-discover` | ICMP + TCP + UDP | Thorough checks where ICMP is filtered |
| `zmap-sweep` | ICMP, line rate | Fastest ICMP-only pass over huge ranges |
| `masscan-sweep` | ICMP + TCP SYN | Fast and reliable across routed networks |
| `arp-scan-sweep` | ARP (L2) | Every host on a directly-connected subnet |
| `nbtscan-sweep` | NetBIOS (UDP 137) | Windows/Samba hosts |

All tools share one CLI:

```
<tool> [-f FILE] [-r RATE] [-l|--local] [-o FILE] [CIDR...]
```

With no targets, they scan the full RFC1918 space. Results are one IP per line on stdout; progress goes to stderr.

## Documentation

- [Tools](docs/tools.md) — per-tool probes, tuning, and limitations
- [Usage](docs/usage.md) — CLI options, target handling, saving results
- [Performance](docs/performance.md) — comparison, worst-case runtimes, enterprise recommendation
- [Bare host](docs/bare-host.md) — run without Docker; full RFC1918 TL;DR
- [Networking](docs/networking.md) — why NAT bridge is the default, and when to use `--net=host`
- [Architecture](docs/architecture.md) — execution flow and shared library diagrams

## License

Copyright (C) 2026 Nic Boet

This program is free software: you can redistribute it and/or modify it under the terms of the GNU General Public License as published by the Free Software Foundation, either version 3 of the License, or (at your option) any later version. See [LICENSE](LICENSE).

The container image bundles third-party tools (nmap, masscan, zmap, fping, arp-scan, nbtscan) installed from Alpine packages; each remains under its own license.
