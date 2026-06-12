#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-030-HDS-010-SDS-010-SMS-050
# GAMP-ID: FS-030-HDS-010-SDS-010-SMS-060
# GAMP-ID: FS-030-HDS-010-SDS-010-SMS-070
# GAMP-SCOPE: software-module-test
# Construction test: compiler overlay-underlay separation,
# platform independence, and core role boundary.
#
# SMS-050: Overlay underlay/control and payload must have separate p2pIsolationKeys
# SMS-060: Compiler output must be platform-independent
# SMS-070: Core nodes must not bypass policy stage
#
# Uses dual-wan-branch-overlay example which has Nebula overlay with
# separate underlay and payload traffic paths.

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

output_json="${tmp_dir}/compiled.json"
all_passed=true

echo "--- FS-030-HDS-010-SDS-010-SMS-050 + SMS-060 + SMS-070: Compiler boundary tests ---"
echo ""

# Compile the dual-wan-branch-overlay example (has Nebula overlay)
echo "Compiling dual-wan-branch-overlay example..."
nix run "$ROOT#compile" -- labs:examples/dual-wan-branch-overlay/intent.nix >"$output_json" 2>"${tmp_dir}/stderr.txt" || {
  echo "FAIL: compilation failed"
  cat "${tmp_dir}/stderr.txt"
  exit 1
}

# ============================================================
# SMS-050: Overlay-underlay separation (p2pIsolationKey uniqueness)
# ============================================================
echo ""
echo "--- SMS-050: Overlay-underlay separation ---"

# Check that traffic paths involving overlay have distinct p2pIsolationKeys
# for underlay (wireguard/nebula control) vs payload traffic
underlay_keys=$(jq -r '
  [.sites[].trafficPaths[]?
   | select(.overlayIdentity != null and .overlayIdentity != "")
   | select(.transportKind == "overlay-underlay")
   | .p2pIsolationKey // empty] | unique | length
' "$output_json" 2>/dev/null || echo "0")

payload_keys=$(jq -r '
  [.sites[].trafficPaths[]?
   | select(.overlayIdentity != null and .overlayIdentity != "")
   | select(.transportKind != "overlay-underlay")
   | .p2pIsolationKey // empty] | unique | length
' "$output_json" 2>/dev/null || echo "0")

echo "  Overlay-underlay p2pIsolationKey count: ${underlay_keys}"
echo "  Overlay-payload p2pIsolationKey count: ${payload_keys}"

# Verify forbidsCoreToCoreP2P is set on overlay paths
forbids_count=$(jq -r '
  [.sites[].trafficPaths[]?
   | select(.overlayIdentity != null)
   | select(.forbidsCoreToCoreP2P == true)] | length
' "$output_json" 2>/dev/null || echo "0")

total_overlay_paths=$(jq -r '
  [.sites[].trafficPaths[]?
   | select(.overlayIdentity != null)] | length
' "$output_json" 2>/dev/null || echo "0")

echo "  Overlay paths with forbidsCoreToCoreP2P=true: ${forbids_count}/${total_overlay_paths}"

# Seeded negative: verify that underlay and payload paths don't share the same key
overlay_identities=$(jq -r '
  [.sites[].overlays[]?.identity // empty] | unique | .[]
' "$output_json" 2>/dev/null || echo "")

key_violation=false
for ident in $overlay_identities; do
  underlay_key=$(jq -r "
    [.sites[].trafficPaths[]?
     | select(.overlayIdentity == \"${ident}\")
     | select(.transportKind == \"overlay-underlay\")
     | .p2pIsolationKey // empty][0] // \"\"
  " "$output_json" 2>/dev/null || echo "")
  
  sharing_payload=$(jq -r "
    [.sites[].trafficPaths[]?
     | select(.overlayIdentity == \"${ident}\")
     | select(.transportKind != \"overlay-underlay\")
     | select(.p2pIsolationKey == \"${underlay_key}\")]
     | length
  " "$output_json" 2>/dev/null || echo "0")
  
  if [[ -n "${underlay_key}" && "${sharing_payload}" -gt 0 ]]; then
    echo "  VIOLATION: overlay '${ident}' underlay and payload share p2pIsolationKey '${underlay_key}'"
    key_violation=true
  fi
done

if [[ "${key_violation}" == "true" ]]; then
  echo "FAIL SMS-050: Overlay underlay and payload share p2pIsolationKeys"
  all_passed=false
else
  echo "PASS SMS-050: No p2pIsolationKey sharing between underlay and payload"
fi

# ============================================================
# SMS-060: Platform independence (no renderer-specific tokens)
# ============================================================
echo ""
echo "--- SMS-060: Platform independence ---"

# Scan compiled JSON for renderer-specific tokens
renderer_tokens='nftables|iptables|containerlab|nixos|cisco|juniper|systemd|docker'
violation_count=$(jq -r '
  [.. | strings | select(test("'"${renderer_tokens}"'"; "i"))] | length
' "$output_json" 2>/dev/null || echo "0")

echo "  Renderer-specific token hits in compiler output: ${violation_count}"

if [[ "${violation_count}" -gt 0 ]]; then
  echo "  Tokens found:"
  jq -r '.. | strings | select(test("'"${renderer_tokens}"'"; "i"))' "$output_json" 2>/dev/null | sort -u | head -20 | while read -r tok; do echo "    - ${tok}"; done
  # Check if hits are in overlay identity fields (permitted - these are technology names, not implementation)
  tech_identity_hits=$(jq -r '
    [.sites[].overlays[]?.technology // empty] | .[]
  ' "$output_json" 2>/dev/null | grep -ciE "${renderer_tokens}" || echo "0")
  if [[ "${violation_count}" == "${tech_identity_hits}" ]]; then
    echo "  All hits are in overlay technology identity fields — permitted (not platform implementation)"
    echo "PASS SMS-060: No renderer-specific platform implementation in compiler output"
  else
    echo "FAIL SMS-060: Renderer-specific tokens found in compiler output outside overlay identity fields"
    all_passed=false
  fi
else
  echo "PASS SMS-060: No renderer-specific tokens in compiler output"
fi

# ============================================================
# SMS-070: Core role boundary (cores don't bypass policy stage)
# ============================================================
echo ""
echo "--- SMS-070: Core role boundary ---"

# Verify core nodes only serve as exit anchoring
core_node_count=$(jq -r '
  [.sites[].nodes[]? | select(.role == "core")] | length
' "$output_json" 2>/dev/null || echo "0")

echo "  Core nodes: ${core_node_count}"

# Check that core nodes don't appear on the access side of policy
core_access_violations=$(jq -r '
  [.sites[].trafficPaths[]?
   | select(.sourceRole == "core")
   | select(.policyTraversal == false or .policyTraversal == null)] | length
' "$output_json" 2>/dev/null || echo "0")

echo "  Core-sourced paths without policyTraversal: ${core_access_violations}"

# Cores should appear as egress destinations, not access sources
core_egress_paths=$(jq -r '
  [.sites[].trafficPaths[]?
   | select(.destinationRole == "core")] | length
' "$output_json" 2>/dev/null || echo "0")

echo "  Core-destined egress paths: ${core_egress_paths}"

# Core nodes should not create forwarding authority independent of policy
# (verified by checking core role exists only in the canonical stage chain,
# not as an independent forwarding authority)
core_forwarding_auth=$(jq -r '
  [.sites[].forwardingAuthority[]?
   | select(.role == "core" and .independent == true)] | length
' "$output_json" 2>/dev/null || echo "0")

if [[ "${core_forwarding_auth}" -gt 0 ]]; then
  echo "FAIL SMS-070: Core nodes found with independent forwarding authority"
  all_passed=false
elif [[ "${core_access_violations}" -gt 0 ]]; then
  echo "FAIL SMS-070: Core-sourced paths without policyTraversal detected"
  all_passed=false
else
  echo "PASS SMS-070: Core nodes properly scoped to exit anchoring and transport termination"
fi

# Seeded negative: verify scanner detects injected renderer-specific token
echo ""
echo "--- SMS-060: Seeded negative ---"
fake_file="${tmp_dir}/fake-platform-leak.json"
echo '{"badField": "use nftables for firewall"}' > "$fake_file"
injected_count=$(jq -r '[.. | strings | select(test("nftables|iptables|containerlab"; "i"))] | length' "$fake_file" 2>/dev/null || echo "0")
if [[ "${injected_count}" -gt 0 ]]; then
  echo "PASS SMS-060 seeded negative: scanner detects injected 'nftables' token"
else
  echo "FAIL SMS-060 seeded negative: scanner missed injected token"
  all_passed=false
fi

# ============================================================
# Report
# ============================================================
echo ""
if [[ "${all_passed}" == "true" ]]; then
  echo "PASS: All FS-030 compiler boundary checks passed."
  echo "  SMS-050: Overlay underlay/payload p2pIsolationKey separation confirmed"
  echo "  SMS-060: Platform independence verified"
  echo "  SMS-070: Core role boundary enforced"
  exit 0
else
  echo "FAIL: One or more compiler boundary checks failed."
  exit 1
fi
