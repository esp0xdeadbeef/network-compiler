#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-030-HDS-010-SDS-030-SMS-010
# GAMP-SCOPE: software-module-test
# Construction test: compiler overlay-underlay separation.
#
# SMS-010: Overlay underlay/control and payload must have separate
# p2pIsolationKeys, transportKind classification, overlayIdentity,
# peerSiteIdentity emission, and explicit underlayAccess validation.
#
# Uses dual-wan-branch-overlay example which has Nebula overlay with
# separate underlay and payload traffic paths.

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

output_json="${tmp_dir}/compiled.json"
all_passed=true

expect_compile_failure() {
  local label="$1"
  local input_file="$2"
  local expected_code="$3"
  local stdout_file="${tmp_dir}/${label}.stdout"
  local stderr_file="${tmp_dir}/${label}.stderr"
  local rc

  set +e
  nix run "$ROOT#compile" -- "$input_file" >"$stdout_file" 2>"$stderr_file"
  rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL ${label}: expected ${expected_code}, but compilation succeeded"
    all_passed=false
    return
  fi

  if grep -q "$expected_code" "$stderr_file"; then
    echo "PASS ${label}: compiler failed closed with ${expected_code}"
  else
    echo "FAIL ${label}: compiler failed, but did not emit ${expected_code}"
    cat "$stderr_file"
    all_passed=false
  fi
}

echo "--- FS-030-HDS-010-SDS-030-SMS-010: Overlay-underlay separation ---"
echo ""

# Compile the dual-wan-branch-overlay example (has Nebula overlay)
echo "Compiling dual-wan-branch-overlay example..."
nix run "$ROOT#compile" -- "${ROOT}/tests/fixtures/examples/dual-wan-branch-overlay/intent.nix" >"$output_json" 2>"${tmp_dir}/stderr.txt" || {
  echo "FAIL: compilation failed"
  cat "${tmp_dir}/stderr.txt"
  exit 1
}

# ============================================================
# P1: Overlay identity and transportKind are emitted
# ============================================================
echo ""
echo "--- P1: Overlay identity fields on overlay traffic paths ---"

overlay_path_count=$(jq -r '
  [.sites[][].trafficPaths[]?
   | select(.overlayIdentity != null)] | length
' "$output_json" 2>/dev/null || echo "0")

underlay_count=$(jq -r '
  [.sites[][].trafficPaths[]?
   | select(.transportKind == "overlay-underlay")] | length
' "$output_json" 2>/dev/null || echo "0")

payload_count=$(jq -r '
  [.sites[][].trafficPaths[]?
   | select(.transportKind == "overlay-payload")] | length
' "$output_json" 2>/dev/null || echo "0")

peer_site_count=$(jq -r '
  [.sites[][].trafficPaths[]?
   | select(.peerSiteIdentity != null)] | length
' "$output_json" 2>/dev/null || echo "0")

echo "  Overlay traffic paths: ${overlay_path_count}"
echo "  Underlay paths (overlay-underlay): ${underlay_count}"
echo "  Payload paths (overlay-payload): ${payload_count}"
echo "  Paths with peerSiteIdentity: ${peer_site_count}"

if [[ "${overlay_path_count}" -gt 0 && "${underlay_count}" -gt 0 && "${payload_count}" -gt 0 && "${peer_site_count}" -gt 0 ]]; then
  echo "PASS P1: overlayIdentity, transportKind, and peerSiteIdentity emitted on overlay paths"
else
  echo "FAIL P1: overlay metadata missing — need overlayIdentity, transportKind, peerSiteIdentity"
  all_passed=false
fi

# ============================================================
# P2: Underlay and payload have distinct p2pIsolationKeys
# (SMS: must not collapse into single relation with shared key)
# ============================================================
echo ""
echo "--- P2: Distinct p2pIsolationKeys for underlay vs payload ---"

# Collect overlay identities
overlay_ids=$(jq -r '
  [.sites[][].trafficPaths[]?
   | select(.overlayIdentity != null)
   | .overlayIdentity] | unique | .[]
' "$output_json" 2>/dev/null || echo "")

key_violation=false
for ident in $overlay_ids; do
  underlay_keys=$(jq -r "
    [.sites[][].trafficPaths[]?
     | select(.overlayIdentity == \"${ident}\" and .transportKind == \"overlay-underlay\")
     | .p2pIsolationKey // empty] | unique
  " "$output_json" 2>/dev/null || echo "[]")
  
  payload_keys=$(jq -r "
    [.sites[][].trafficPaths[]?
     | select(.overlayIdentity == \"${ident}\" and .transportKind == \"overlay-payload\")
     | .p2pIsolationKey // empty] | unique
  " "$output_json" 2>/dev/null || echo "[]")
  
  # Check if any underlay key appears in payload keys
  shared=$(jq -rn "
    ([${underlay_keys}] + [${payload_keys}]) as \$all
    | ([${underlay_keys}] - ([${underlay_keys}] - [${payload_keys}])) | length
  " 2>/dev/null || echo "0")
  
  underlay_count_single=$(jq -rn "[${underlay_keys}] | length" 2>/dev/null || echo "0")
  payload_count_single=$(jq -rn "[${payload_keys}] | length" 2>/dev/null || echo "0")
  
  echo "  Overlay '${ident}': underlay=${underlay_count_single} payload=${payload_count_single} shared=${shared}"
  
  if [[ "${shared}" -gt 0 ]]; then
    echo "  VIOLATION: overlay '${ident}' underlay and payload share p2pIsolationKey(s)"
    key_violation=true
  fi
done

if [[ "${key_violation}" == "true" ]]; then
  echo "FAIL P2: Overlay underlay and payload share p2pIsolationKeys"
  all_passed=false
else
  echo "PASS P2: No p2pIsolationKey sharing between underlay and payload"
fi

# ============================================================
# P3: forbidsCoreToCoreP2P on all overlay paths
# ============================================================
echo ""
echo "--- P3: forbidsCoreToCoreP2P on overlay paths ---"

forbids_count=$(jq -r '
  [.sites[][].trafficPaths[]?
   | select(.overlayIdentity != null)
   | select(.forbidsCoreToCoreP2P == true)] | length
' "$output_json" 2>/dev/null || echo "0")

forbids_false_count=$(jq -r '
  [.sites[][].trafficPaths[]?
   | select(.overlayIdentity != null)
   | select(.forbidsCoreToCoreP2P == false)] | length
' "$output_json" 2>/dev/null || echo "0")

echo "  Overlay paths with forbidsCoreToCoreP2P=true: ${forbids_count}"
echo "  Overlay paths with forbidsCoreToCoreP2P=false: ${forbids_false_count}"

if [[ "${forbids_count}" -gt 0 && "${forbids_false_count}" -eq 0 ]]; then
  echo "PASS P3: All overlay paths have forbidsCoreToCoreP2P=true"
else
  echo "FAIL P3: Some overlay paths missing forbidsCoreToCoreP2P=true"
  all_passed=false
fi

# ============================================================
# N1: Seeded negative — verify scanner detects violation
# ============================================================
echo ""
echo "--- N1: Seeded negative — collapsed underlay/payload detection ---"

fake_file="${tmp_dir}/fake-collapsed.json"
cat > "$fake_file" << 'EOF'
{
  "sites": {
    "test": {
      "site-x": {
        "trafficPaths": [
          {
            "relationId": "underlay-rel",
            "overlayIdentity": "test-overlay",
            "transportKind": "overlay-underlay",
            "p2pIsolationKey": "SHARED-KEY-001",
            "forbidsCoreToCoreP2P": true,
            "peerSiteIdentity": "peer.site"
          },
          {
            "relationId": "payload-rel",
            "overlayIdentity": "test-overlay",
            "transportKind": "overlay-payload",
            "p2pIsolationKey": "SHARED-KEY-001",
            "forbidsCoreToCoreP2P": true,
            "peerSiteIdentity": "peer.site"
          }
        ]
      }
    }
  }
}
EOF

# Run the same check against the seeded negative
seeded_overlay_ids=$(jq -r '
  [.sites[][].trafficPaths[]?
   | select(.overlayIdentity != null)
   | .overlayIdentity] | unique | .[]
' "$fake_file" 2>/dev/null || echo "")

seeded_violation_detected=false
for ident in $seeded_overlay_ids; do
  seeded_underlay_keys=$(jq -r "
    [.sites[][].trafficPaths[]?
     | select(.overlayIdentity == \"${ident}\" and .transportKind == \"overlay-underlay\")
     | .p2pIsolationKey // empty] | unique
  " "$fake_file" 2>/dev/null || echo "[]")
  
  seeded_payload_keys=$(jq -r "
    [.sites[][].trafficPaths[]?
     | select(.overlayIdentity == \"${ident}\" and .transportKind == \"overlay-payload\")
     | .p2pIsolationKey // empty] | unique
  " "$fake_file" 2>/dev/null || echo "[]")
  
  seeded_shared=$(jq -rn "
    ([${seeded_underlay_keys}] + [${seeded_payload_keys}]) as \$all
    | ([${seeded_underlay_keys}] - ([${seeded_underlay_keys}] - [${seeded_payload_keys}])) | length
  " 2>/dev/null || echo "0")
  
  if [[ "${seeded_shared}" -gt 0 ]]; then
    seeded_violation_detected=true
    echo "  Seeded negative DETECTED: overlay '${ident}' shares p2pIsolationKey 'SHARED-KEY-001'"
  fi
done

if [[ "${seeded_violation_detected}" == "true" ]]; then
  echo "PASS N1: Seeded negative — scanner detects collapsed p2pIsolationKeys"
else
  echo "FAIL N1: Seeded negative — scanner did not detect shared p2pIsolationKeys"
  all_passed=false
fi

# ============================================================
# N2: Seeded negative — missing explicit underlayAccess
# ============================================================
echo ""
echo "--- N2: Seeded negative — missing explicit underlayAccess ---"

expect_compile_failure \
  "N2 missing underlayAccess" \
  "${ROOT}/tests/negative/overlay-access-attachment-missing.nix" \
  "E_OVERLAY_UNDERLAY_ACCESS_REQUIRED"

# ============================================================
# N3: Seeded negative — underlayAccess tenant lacks WAN egress
# ============================================================
echo ""
echo "--- N3: Seeded negative — underlayAccess tenant lacks WAN egress ---"

bad_underlay_egress="${tmp_dir}/overlay-underlay-no-wan-egress.nix"
cat > "$bad_underlay_egress" <<'EOF'
{
  acme = {
    ams = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };

      ownership.prefixes = [
        { kind = "tenant"; name = "hostile"; ipv4 = "10.20.70.0/24"; }
        { kind = "tenant"; name = "client"; ipv4 = "10.20.20.0/24"; }
      ];

      communicationContract = {
        trafficTypes = [
          { name = "nebula"; match = [ { proto = "udp"; dports = [ 4242 ]; family = "any"; } ]; }
        ];
        services = [ ];
        relations = [
          {
            id = "allow-hostile-to-overlay";
            priority = 100;
            from = { kind = "tenant"; name = "hostile"; };
            to = { kind = "external"; name = "east-west"; };
            trafficType = "any";
            action = "allow";
          }
          {
            id = "allow-client-to-wan";
            priority = 101;
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "external"; name = "wan"; };
            trafficType = "any";
            action = "allow";
          }
          {
            id = "allow-east-west-underlay-to-wan";
            priority = 110;
            from = { kind = "external"; name = "east-west"; };
            to = { kind = "external"; name = "wan"; };
            trafficType = "nebula";
            action = "allow";
          }
        ];
      };

      transport.overlays = [
        {
          name = "east-west";
          terminateOn = "core-overlay";
          underlayAccess = { kind = "tenant"; name = "hostile"; };
          underlayTrafficTypes = [ "nebula" ];
          mustTraverse = [ "policy" ];
        }
      ];

      topology.nodes = {
        core-wan = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; };
        core-overlay = {
          role = "core";
          attachments = [ { kind = "tenant"; name = "hostile"; } ];
          uplinks.east-west.ipv4 = [ "100.96.20.0/24" ];
        };
        upstream = { role = "upstream-selector"; };
        policy = { role = "policy"; };
        downstream = { role = "downstream-selector"; };
        access-hostile = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "hostile"; } ];
        };
        access-client = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
        };
      };

      topology.links = [
        [ "core-wan" "upstream" ]
        [ "upstream" "policy" ]
        [ "policy" "downstream" ]
        [ "downstream" "access-hostile" ]
        [ "downstream" "access-client" ]
      ];
    };
  };
}
EOF

expect_compile_failure \
  "N3 underlayAccess without WAN egress" \
  "$bad_underlay_egress" \
  "E_OVERLAY_UNDERLAY_ACCESS_WAN_EGRESS_REQUIRED"

# ============================================================
# Report
# ============================================================
echo ""
if [[ "${all_passed}" == "true" ]]; then
  echo "PASS: FS-030-HDS-010-SDS-030-SMS-010 overlay-underlay separation verified."
  echo "  P1: overlayIdentity, transportKind, peerSiteIdentity emitted on overlay paths"
  echo "  P2: Distinct p2pIsolationKeys for underlay vs payload (no collapse)"
  echo "  P3: forbidsCoreToCoreP2P=true on all overlay paths"
  echo "  N1: Seeded negative detects shared p2pIsolationKey"
  echo "  N2: Missing explicit underlayAccess fails closed"
  echo "  N3: Underlay access without WAN egress fails closed"
  exit 0
else
  echo "FAIL: One or more overlay-underlay separation checks failed."
  exit 1
fi
