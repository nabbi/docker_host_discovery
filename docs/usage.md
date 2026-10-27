# Usage

All six tools share the same CLI:

```
Usage: <tool> [OPTIONS] [CIDR...]

  -f, --file FILE    Read targets from file (one CIDR/line)
  -r, --rate NUM     Packets per second (tool-specific default)
  -l, --local        Auto-detect local RFC1918 subnets
  -o, --output FILE  Write results to file (default: stdout)
  -h, --help         Show usage
```

## Targets

Targets may be CIDRs or bare IPv4 addresses (treated as `/32`); anything else is rejected.

If no targets are specified, all tools default to scanning the full RFC1918 space via `rfc1918.conf`. `--local` exits with an error if no RFC1918 subnets are found, rather than falling back to the full space. Under Docker's NAT bridge, `--local` sees the bridge subnet rather than the host's LANs — see [networking](networking.md).

## Output

One alive IP per line, numerically sorted, on stdout. Progress and warnings go to stderr, so standard redirection works:

```bash
# Save to file
docker run --rm host-discovery fping-sweep 10.0.0.0/24 > alive.txt

# Pipe to another tool
docker run --rm host-discovery fping-sweep 10.0.0.0/24 | wc -l

# Use the built-in -o flag (needs a bind mount)
docker run --rm -v "$PWD":/output host-discovery fping-sweep 10.0.0.0/24 -o /output/alive.txt
```
