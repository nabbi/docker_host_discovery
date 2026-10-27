# Running on a Bare Host

## TL;DR — Full RFC1918

```bash
git clone https://github.com/nabbi/docker_host_discovery.git
cd docker_host_discovery
sudo apt install fping nmap zmap masscan arp-scan nbtscan iproute2   # see below for other distros

# Routed networks: full RFC1918 (no targets = 10/8, 172.16/12, 192.168/16)
sudo bin/masscan-sweep -r 100000 > alive.txt

# Directly-connected subnets: masscan/zmap miss these on a bare host, so add ARP
sudo bin/arp-scan-sweep --local >> alive.txt

sort -u -t. -k1,1n -k2,2n -k3,3n -k4,4n alive.txt -o alive.txt
```

~24 minutes for the masscan pass at 100K pps, plus seconds for ARP. Lower `-r` if firewalls or WAN links in the path can't keep up — see [performance](performance.md).

> **Only scan networks you own or are authorized to test.**

## Install

The scripts run straight from `bin/` — no install step. They need bash and whichever scanners you use:

| Distro | Command |
|--------|---------|
| Debian / Ubuntu | `sudo apt install fping nmap zmap masscan arp-scan nbtscan iproute2` |
| Alpine | `apk add bash fping nmap zmap masscan arp-scan nbtscan libpcap-dev iproute2-minimal` |
| Gentoo | `emerge net-analyzer/{fping,nmap,zmap,masscan,arp-scan,nbtscan}` |

`rfc1918.conf` is read from `bin/` next to the scripts, so they also work if you copy `bin/` elsewhere (for example `/usr/local/bin`, as the container does).

## Why the ARP Pass

On a bare host, zmap and masscan see the same thing as a container with `--net=host`: they send every probe to the default gateway's MAC and never ARP individual hosts. Hosts on your directly-connected subnets are reached through the router, which usually won't hairpin the traffic back, so they go missing. `arp-scan-sweep --local` fills that gap. See [networking](networking.md) for the full explanation.

`--local` works properly on a bare host — it reads the host's real routing table, unlike under Docker's NAT bridge.

## Privileges

| Tool | Needs root |
|------|------------|
| masscan-sweep, zmap-sweep, arp-scan-sweep | Yes (raw sockets) |
| nmap-discover | Recommended — some probe types are limited without it |
| fping-sweep, nbtscan-sweep | No (fping may need setuid or `CAP_NET_RAW` depending on distro) |

## Other Full-Space Options

```bash
sudo bin/zmap-sweep > alive.txt           # ~3 min, ICMP only — quick first look
sudo bin/nmap-discover -o alive.txt       # most thorough, but ~18 hours at defaults
```
