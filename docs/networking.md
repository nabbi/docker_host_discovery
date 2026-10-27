# Networking: NAT Bridge vs Host Mode

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
