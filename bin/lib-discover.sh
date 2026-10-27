#!/usr/bin/env bash
# SPDX-License-Identifier: GPL-3.0-or-later
# lib-discover.sh — shared functions for host-discovery scripts
# Source this; do not execute directly.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[1]:-${BASH_SOURCE[0]}}")" && pwd)"
DEFAULT_CONF="${SCRIPT_DIR}/rfc1918.conf"
# Fallback if installed to /usr/local/bin
[[ -f "$DEFAULT_CONF" ]] || DEFAULT_CONF="/usr/local/bin/rfc1918.conf"

# --- Argument parsing ---------------------------------------------------

TARGETS=()
TARGET_FILE=""
RATE=""
LOCAL_MODE=0
OUTPUT=""

usage() {
    local tool
    tool="$(basename "$0")"
    cat >&2 <<EOF
Usage: ${tool} [OPTIONS] [CIDR...]

  -f, --file FILE    Read targets from file (one CIDR/line)
  -r, --rate NUM     Packets per second (tool-specific default)
  -l, --local        Auto-detect local subnets
  -o, --output FILE  Write results to file (default: stdout)
  -h, --help         Show usage

Output: one alive IP per line, numerically sorted, to stdout.
        Progress/warnings to stderr.
EOF
    exit "${1:-0}"
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -f|--file)
                [[ -n "${2:-}" ]] || { echo "Error: $1 requires an argument" >&2; exit 1; }
                TARGET_FILE="$2"; shift 2 ;;
            -r|--rate)
                [[ -n "${2:-}" ]] || { echo "Error: $1 requires an argument" >&2; exit 1; }
                [[ "$2" =~ ^[1-9][0-9]*$ ]] || { echo "Error: rate must be a positive integer: $2" >&2; exit 1; }
                # shellcheck disable=SC2034  # read by the sourcing scripts
                RATE="$2"; shift 2 ;;
            -l|--local)
                LOCAL_MODE=1; shift ;;
            -o|--output)
                [[ -n "${2:-}" ]] || { echo "Error: $1 requires an argument" >&2; exit 1; }
                OUTPUT="$2"; shift 2 ;;
            -h|--help)
                usage 0 ;;
            --)
                shift; TARGETS+=("$@"); break ;;
            -*)
                echo "Unknown option: $1" >&2; usage 1 ;;
            *)
                TARGETS+=("$1"); shift ;;
        esac
    done
}

# Populate TARGETS from all sources; fall back to rfc1918.conf.
resolve_targets() {
    # --local: detect connected RFC1918 subnets
    if [[ "$LOCAL_MODE" -eq 1 ]]; then
        local nets
        nets="$(detect_local_subnets)"
        if [[ -z "$nets" ]]; then
            # Don't fall through to the full RFC1918 default
            echo "Error: --local found no RFC1918 subnets" >&2
            exit 1
        else
            while IFS= read -r net; do
                TARGETS+=("$net")
            done <<< "$nets"
        fi
    fi

    # --file: read CIDRs from file
    if [[ -n "$TARGET_FILE" ]]; then
        [[ -f "$TARGET_FILE" ]] || { echo "Error: target file not found: $TARGET_FILE" >&2; exit 1; }
        while IFS= read -r line; do
            line="${line%%#*}"          # strip comments
            line="${line// /}"          # strip whitespace
            [[ -n "$line" ]] && TARGETS+=("$line")
        done < "$TARGET_FILE"
    fi

    # Default to rfc1918.conf when nothing else specified
    if [[ ${#TARGETS[@]} -eq 0 ]]; then
        if [[ -f "$DEFAULT_CONF" ]]; then
            echo "No targets specified; defaulting to ${DEFAULT_CONF}" >&2
            while IFS= read -r line; do
                line="${line%%#*}"
                line="${line// /}"
                [[ -n "$line" ]] && TARGETS+=("$line")
            done < "$DEFAULT_CONF"
        else
            echo "Error: no targets and ${DEFAULT_CONF} not found" >&2
            exit 1
        fi
    fi

    # Validate and normalize: bare IPs become /32
    local i
    for i in "${!TARGETS[@]}"; do
        valid_target "${TARGETS[$i]}" || { echo "Error: invalid IPv4 address or CIDR: ${TARGETS[$i]}" >&2; exit 1; }
        [[ "${TARGETS[$i]}" == */* ]] || TARGETS[i]="${TARGETS[$i]}/32"
    done

    # Warn on large target space
    local total=0
    for cidr in "${TARGETS[@]}"; do
        total=$(( total + $(count_addresses "$cidr") ))
    done
    if [[ $total -gt 1000000 ]]; then
        printf "Warning: target space contains ~%'d addresses\n" "$total" >&2
    fi
}

# --- Local subnet detection ---------------------------------------------

detect_local_subnets() {
    # Return RFC1918 subnets from directly-connected routes
    ip -4 route show scope link 2>/dev/null | awk '{print $1}' | while IFS= read -r net; do
        case "$net" in
            10.*|172.1[6-9].*|172.2[0-9].*|172.3[01].*|192.168.*) echo "$net" ;;
        esac
    done
}

# --- CIDR math (pure bash, 32-bit) --------------------------------------

valid_target() {
    # Accept a.b.c.d or a.b.c.d/n. Must run before any arithmetic on targets:
    # bash evaluates expressions inside $(( )), so unvalidated input is unsafe.
    local re='^([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})(/([0-9]{1,2}))?$'
    [[ "$1" =~ $re ]] || return 1
    local n
    for n in 1 2 3 4; do
        (( 10#${BASH_REMATCH[n]} <= 255 )) || return 1
    done
    [[ -z "${BASH_REMATCH[6]}" ]] || (( 10#${BASH_REMATCH[6]} <= 32 ))
}

ip_to_int() {
    local -a o
    IFS=. read -ra o <<< "$1"
    echo $(( (o[0] << 24) + (o[1] << 16) + (o[2] << 8) + o[3] ))
}

int_to_ip() {
    local n=$1
    echo "$(( (n >> 24) & 255 )).$(( (n >> 16) & 255 )).$(( (n >> 8) & 255 )).$(( n & 255 ))"
}

split_cidr() {
    # Split a CIDR into /17 chunks (fping limit: 131072 = 2^17 addresses).
    # Usage: split_cidr 10.0.0.0/8  →  prints one /17 per line
    local cidr="$1"
    local max_prefix="${2:-17}"

    local ip prefix
    ip="${cidr%/*}"
    prefix="${cidr#*/}"

    if [[ "$prefix" -ge "$max_prefix" ]]; then
        echo "$cidr"
        return
    fi

    # Mask to the network address so chunks stay aligned (10.1.2.3/15 → 10.0.0.0)
    local base
    base=$(( $(ip_to_int "$ip") & ~((1 << (32 - prefix)) - 1) & 0xFFFFFFFF ))
    local chunk_size=$(( 1 << (32 - max_prefix) ))
    local total=$(( 1 << (32 - prefix) ))
    local i=0

    while [[ $i -lt $total ]]; do
        printf '%s/%d\n' "$(int_to_ip $(( base + i )))" "$max_prefix"
        i=$(( i + chunk_size ))
    done
}

count_addresses() {
    local cidr="$1"
    local prefix="${cidr#*/}"
    # Handle bare IPs (no /prefix)
    if [[ "$prefix" == "$cidr" ]]; then
        echo 1
        return
    fi
    echo $(( 1 << (32 - prefix) ))
}

# --- Output helpers ------------------------------------------------------

sort_ips() {
    sort -u -t. -k1,1n -k2,2n -k3,3n -k4,4n
}

output_results() {
    if [[ -n "$OUTPUT" ]]; then
        sort_ips | tee "$OUTPUT"
    else
        sort_ips
    fi
}
