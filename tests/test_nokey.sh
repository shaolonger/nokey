#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck source=/dev/null
source "$REPO_ROOT/nokey.sh"

pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; exit 1; }

# Test 1: netstack=4 resolves IP after detection values exist
netstack=""
ip=""
IPv4="198.51.100.10"
IPv6="2001:db8::10"
port="12345"
domain="example.com"
caddy_mode=0
initialize_variables >/dev/null 2>&1 || fail "initialize_variables auto mode"
[[ "$netstack" == "4" ]] || fail "auto netstack should prefer IPv4"
[[ "$ip" == "$IPv4" ]] || fail "auto netstack should assign IPv4 ip"
pass "auto netstack IP assignment"

# Test 2: explicit netstack=6 assigns IPv6 IP
netstack="6"
ip=""
IPv4="198.51.100.11"
IPv6="2001:db8::11"
port="12346"
domain="example.com"
caddy_mode=0
initialize_variables >/dev/null 2>&1 || fail "initialize_variables netstack=6"
[[ "$ip" == "$IPv6" ]] || fail "netstack=6 should assign IPv6 ip"
pass "explicit netstack=6 IP assignment"

# Test 3: public key extraction from xray x25519 output
keys_sample=$'PrivateKey: PRIVATE_VALUE\nPublicKey: PUBLIC_VALUE'
extracted="$(extract_public_key_from_x25519_output "$keys_sample")"
[[ "$extracted" == "PUBLIC_VALUE" ]] || fail "public key extraction should return PUBLIC_VALUE"
pass "public key extraction"

# Test 4: key extraction supports spaced labels used by some xray builds
keys_sample_spaced=$'Private key: PRIVATE_SPACED\nPublic key: PUBLIC_SPACED'
extracted_private="$(extract_private_key_from_x25519_output "$keys_sample_spaced")"
extracted_public="$(extract_public_key_from_x25519_output "$keys_sample_spaced")"
[[ "$extracted_private" == "PRIVATE_SPACED" ]] || fail "private key extraction should support 'Private key:' format"
[[ "$extracted_public" == "PUBLIC_SPACED" ]] || fail "public key extraction should support 'Public key:' format"
pass "spaced label key extraction"

# Test 5: architecture mapping helper
[[ "$(resolve_arch_dir x86_64)" == "binary_amd64" ]] || fail "x86_64 should map to binary_amd64"
[[ "$(resolve_arch_dir amd64)" == "binary_amd64" ]] || fail "amd64 should map to binary_amd64"
[[ "$(resolve_arch_dir aarch64)" == "binary_arm64" ]] || fail "aarch64 should map to binary_arm64"
[[ "$(resolve_arch_dir arm64)" == "binary_arm64" ]] || fail "arm64 should map to binary_arm64"
if resolve_arch_dir mips >/dev/null 2>&1; then
  fail "unsupported architecture should fail"
fi
pass "architecture mapping helper"

# Test 6: OS family helper
ID="alpine"
ID_LIKE=""
[[ "$(resolve_os_family)" == "alpine" ]] || fail "ID=alpine should map to alpine"
ID="debian"
ID_LIKE="debian"
[[ "$(resolve_os_family)" == "debian/systemd-compatible" ]] || fail "debian-like should map to debian/systemd-compatible"
pass "os family helper"

# Test 7: dry-run output includes expected download and service lines
ID="alpine"
ID_LIKE=""
dry_run_out="$(dry_run_preview 2>&1 || true)"
echo "$dry_run_out" | grep -Eq 'binary_(amd64|arm64)/xray -> /usr/local/bin/xray' || fail "dry-run should include xray download path"
[[ "$dry_run_out" == *"/etc/init.d/xray"* ]] || fail "dry-run alpine should include OpenRC path"
pass "dry-run preview output"

# Test 8: BBR guard/message exists for readonly environments
enable_bbr_source="$(declare -f enable_bbr)"
[[ "$enable_bbr_source" == *'[[ ! -w /etc/sysctl.conf ]]'* ]] || fail "enable_bbr should check writable sysctl.conf"
[[ "$enable_bbr_source" == *'Skip BBR: /etc/sysctl.conf is not writable'* ]] || fail "enable_bbr should expose clear skip message"
pass "bbr readonly guard present"

echo "All tests passed."
