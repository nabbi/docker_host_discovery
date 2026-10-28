# Running on Windows

The `bin/` scripts are bash and call Linux builds of the scanners, so they don't run natively on Windows. There are five ways to scan from a Windows machine:

| Option | Tools available | Notes |
|--------|-----------------|-------|
| **Docker Desktop** (recommended) | All except `arp-scan-sweep` | Same commands as the [README](../README.md). Containers run inside a Linux VM, so ARP can't reach your physical LAN. |
| **WSL2** | All except `arp-scan-sweep` | Follow [bare host](bare-host.md) inside your distro. Default NAT networking hides the LAN at L2, like Docker's bridge. |
| **Bridged Linux VM** | All six | The only option that puts Linux directly on your LAN — see [below](#bridged-linux-vm). |
| **Git Bash** | `nmap-discover`, `masscan-sweep` | Runs the `bin/` scripts against Windows nmap/masscan — see [below](#git-bash). No `--local`. |
| **Native commands** | nmap, masscan, nbtscan | Run the scanners directly from PowerShell — see [below](#native-commands). |

> **Only scan networks you own or are authorized to test.**

For local-subnet discovery (what `arp-scan-sweep --local` does on Linux), use a bridged VM or native nmap — nmap ARP-pings directly-connected targets automatically.

## Bridged Linux VM

A VM attached to a bridged (external) network gets its own MAC and IP on your physical LAN, so it behaves like a [bare host](bare-host.md): every tool works, including `arp-scan-sweep --local`.

**Hyper-V** — create an External switch bound to your physical adapter, then attach the VM to it:

```powershell
Get-NetAdapter                                         # find the adapter name
New-VMSwitch -Name LAN -NetAdapterName "Ethernet" -AllowManagementOS $true
Connect-VMNetworkAdapter -VMName <vm> -SwitchName LAN
```

**VirtualBox / VMware Workstation** — set the VM's network adapter to *Bridged* and pick your physical adapter.

Then, inside the VM, either follow [bare host](bare-host.md) or use Docker with `--net=host` for `arp-scan-sweep` (the VM is on the LAN, so host networking now reaches it).

Prefer a wired adapter. Wi-Fi bridging has to rewrite the VM's MAC to the host's (access points only accept the associated MAC), which can make ARP results from the VM unreliable.

## Git Bash

[Git for Windows](https://gitforwindows.org/) ships bash and GNU coreutils, which is enough for the `bin/` scripts to drive the Windows builds of nmap and masscan.

1. Install nmap and masscan (see [availability](#native-tool-availability)) and make sure `nmap.exe` and `masscan.exe` are on `PATH`.
2. Open Git Bash **as Administrator**.
3. Run the scripts from the repo:

```bash
bin/masscan-sweep -r 100000 > alive.txt
bin/nmap-discover -o alive.txt 10.0.0.0/16
```

Limitations:

- Only `nmap-discover` and `masscan-sweep` work. fping, zmap and arp-scan have no Windows builds, and the Windows `nbtscan.exe` takes different options than the script passes.
- `--local` fails — it reads routes with Linux `ip`. Pass CIDRs or `-f FILE` instead (see the [`Get-NetIPAddress` snippet](#directly-connected-subnets--nmap-arp) to list them).
- The repo's `.gitattributes` keeps `bin/` scripts LF on checkout. If bash reports `$'\r': command not found`, the files were checked out with CRLF before that rule existed; refresh them with `rm bin/* && git checkout -- bin`.

## Native Tool Availability

| Tool | Native Windows build | Get it |
|------|----------------------|--------|
| nmap | Yes, official | [nmap.org](https://nmap.org/download.html#windows) or `winget install Insecure.Nmap` — installer bundles Npcap |
| masscan | Yes, but no official binary | Build from [source](https://github.com/robertdavidgraham/masscan) with Visual Studio or MinGW. Needs [Npcap](https://npcap.com/) installed in WinPcap API-compatible mode. Tops out around 300K pps on Windows. |
| nbtscan | Yes, different program | Steve Friedl's [unixwiz nbtscan](http://www.unixwiz.net/tools/nbtscan.html) (`nbtscan.exe`). Not the same CLI as the Linux nbtscan. |
| fping | No | Cygwin builds only. Use nmap `-PE` instead. |
| zmap | No | Linux/BSD/macOS only. Use masscan instead. |
| arp-scan | No | Use `nmap -sn -PR` on local subnets. |

Run PowerShell **as Administrator** for nmap and masscan — raw packet probes and ARP need it.

## Native Commands

The commands below reproduce what each wrapper script runs, with one alive IP per line written to a file. They use PowerShell for the parsing that `awk` does in the scripts.

### Routed networks — masscan (recommended for large ranges)

Equivalent to `masscan-sweep -r 100000` over the full RFC1918 space (~24 minutes):

```powershell
masscan 10.0.0.0/8 172.16.0.0/12 192.168.0.0/16 `
    -p80,443,22,8080,8443,3389,445 --ping `
    --rate 100000 --wait 2 --open-only -oL - |
  ForEach-Object { if ($_ -match '^open') { ($_ -split '\s+')[3] } } |
  Set-Content alive.txt
```

If masscan picks the wrong interface, add `--adapter <name>`; `masscan --iflist` lists them.

### Thorough check — nmap

Equivalent to `nmap-discover` (catches hosts that drop ICMP):

```powershell
nmap -sn -n -PE -PP -PS22,80,443,8080 -PA80,443 -PU40125 `
    -T4 --min-rate 5000 --min-hostgroup 256 --max-retries 1 `
    --max-rtt-timeout 200ms --initial-rtt-timeout 100ms `
    -oG - 10.0.0.0/16 |
  Select-String 'Status: Up' |
  ForEach-Object { ($_.Line -split '\s+')[1] } |
  Set-Content alive.txt
```

Full RFC1918 with nmap takes ~18 hours at these settings; prefer masscan for that.

### Directly-connected subnets — nmap ARP

Replaces `arp-scan-sweep --local`. Detect the RFC1918 subnets on your active adapters, then ARP-scan them:

```powershell
$subnets = Get-NetIPAddress -AddressFamily IPv4 -AddressState Preferred |
  Where-Object { $_.IPAddress -match '^(10\.|172\.(1[6-9]|2[0-9]|3[01])\.|192\.168\.)' } |
  ForEach-Object { "$($_.IPAddress)/$($_.PrefixLength)" }

nmap -sn -n -PR -oG - $subnets |
  Select-String 'Status: Up' |
  ForEach-Object { ($_.Line -split '\s+')[1] } |
  Add-Content alive.txt
```

nmap normalizes `192.168.1.23/24` to the whole subnet, so passing the host address is fine.

### Windows hosts — nbtscan

Equivalent in spirit to `nbtscan-sweep`. The unixwiz `nbtscan.exe` prints one host per line starting with the IP:

```powershell
.\nbtscan.exe 192.168.1.0/24 |
  ForEach-Object { if ($_ -match '^(\d+\.\d+\.\d+\.\d+)') { $Matches[1] } } |
  Add-Content alive.txt
```

Run `nbtscan.exe` with no arguments for its own options (timeouts and verbosity differ from the Linux tool).

### Merge and sort results

Equivalent to the scripts' `sort -u` by octet:

```powershell
(Get-Content alive.txt) | Sort-Object { [version]$_ } -Unique | Set-Content alive.txt
```
