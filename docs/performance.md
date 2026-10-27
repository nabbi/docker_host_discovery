# Performance

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

## Worst-Case Runtimes

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

## Enterprise Recommendation

**Use `masscan-sweep` with a raised rate.** It is the best balance of reliability and speed for large routed networks:

- **Reliable:** ICMP plus TCP SYN on 7 common ports finds hosts that drop ping — Windows Firewall blocks ICMP echo by default, so ICMP-only tools (zmap, fping) undercount in enterprise environments.
- **Fast:** stateless and asynchronous like zmap, so throughput scales with `-r` rather than with timeouts. Its 10K pps default is conservative; at `-r 100000` the full RFC1918 space takes ~24 minutes, versus ~18 hours for nmap.
- **Routed:** works through the NAT bridge across L3 boundaries, unlike arp-scan.

```bash
docker run --rm --privileged -v "$PWD":/work host-discovery \
    masscan-sweep -r 100000 -f /work/targets.txt > alive.txt
```

Scope `targets.txt` to your allocated ranges (IPAM export) rather than all of RFC1918 — runtime scales linearly with address count. Pick the rate your firewalls, IDS, and WAN links tolerate; stateful firewalls in the path are usually the bottleneck before the scanner is.

Complement as needed:

- `zmap-sweep` for a ~3 minute ICMP-only first pass when you need a quick answer.
- `arp-scan-sweep --local` on each segment where you have a foothold — the only method that catches fully firewalled hosts.
- `nmap-discover` for a targeted follow-up on ranges where masscan found nothing but hosts are expected.
