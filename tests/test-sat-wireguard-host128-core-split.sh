#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-COMP-SAT-WIREGUARD-HOST128-CORE-SPLIT-001
# GAMP-SCOPE: software-module-test
# CMC: Compiler construction test for WireGuard host128 core split (SAT fixtures)
#
# Predicates proven:
#   - WG overlay terminates on correct host (hetz-router-nebula-core)
#   - Segmented overlay IPAM (distinct prefixes per overlay)
#   - WAN egress routes through non-overlay core (hetz-router-core)
#
# Active seeded negatives:
#   Negative 1 — Overlay terminateOn non-core node (E_OVERLAY_TERMINATE_NON_CORE)
#   Negative 2 — Ambiguous core (multiple cores, no terminateOn) (E_OVERLAY_AMBIGUOUS_CORE)
#   Negative 3 — Overlay terminateOn unknown node (E_OVERLAY_UNKNOWN_TERMINATION)

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

all_passed=true

# Resolve network-labs root for sat/intent.nix
archive_json="${tmp_dir}/archive.json"
nix flake archive --json "path:${ROOT}" > "${archive_json}"
labs_root="$(jq -er '.inputs["network-labs"].path' "${archive_json}")"
sat_intent="${labs_root}/GAMP/SAT/intent.nix"

if [[ ! -f "${sat_intent}" ]]; then
  echo "FAIL: sat/intent.nix not found at ${sat_intent}" >&2
  exit 1
fi

fail() {
  echo "FAIL: $1" >&2
  all_passed=false
}

expect_compile_failure() {
  local name="$1"
  local input="$2"
  local expected_error="$3"
  local output
  local rc

  set +e
  output="$(nix run "${ROOT}#compile" -- "${input}" 2>&1)"
  rc=$?
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    fail "${name}: expected compiler failure but compiled successfully"
    return
  fi

  if ! echo "${output}" | grep -q "${expected_error}"; then
    fail "${name}: missing ${expected_error} in compiler output"
    echo "${output}" >&2
    return
  fi

  echo "PASS: ${name}"
}

# ============================================================
# Positive: Compile sat/intent.nix and validate WG overlay properties
# ============================================================
echo "--- Positive: WireGuard host128 core split (sat/intent.nix) ---"

compiled_json="${tmp_dir}/sat-compiled.json"
nix run "${ROOT}#compile" -- "${sat_intent}" > "${compiled_json}"

# Verify overlay terminates on correct host
echo "  Checking overlay termination..."
jq -e '
  .sites.esp.hetz.overlayAttachments["wg-host128-egress"].terminatesOn == ["hetz-router-nebula-core"]
  and .sites.esp.hetz.overlayAttachments["wg-routed64"].terminatesOn == ["hetz-router-nebula-core"]
' "${compiled_json}" >/dev/null || fail "WG overlay terminateOn: expected hetz-router-nebula-core"

echo "PASS: WG overlays terminate on hetz-router-nebula-core"

# Verify WAN egress core is hetz-router-core (not nebula-core)
echo "  Checking WAN egress core..."
jq -e '
  .sites.esp.hetz.overlayAttachments["wg-host128-egress"].canonicalPath[0] == "hetz-router-core"
  and .sites.esp.hetz.overlayAttachments["wg-routed64"].canonicalPath[0] == "hetz-router-core"
' "${compiled_json}" >/dev/null || fail "WG overlay WAN egress: expected hetz-router-core as ingress core"

echo "PASS: WAN egress routes through hetz-router-core (non-overlay core)"

# Verify segmented overlay IPAM
echo "  Checking segmented overlay IPAM..."
jq -e '
  .sites.esp.hetz.overlayAddressPools["wg-host128-egress"].ipv4.prefix == "10.66.128.0/24"
  and .sites.esp.hetz.overlayAddressPools["wg-routed64"].ipv4.prefix == "10.66.64.0/24"
  and .sites.esp.hetz.overlayAddressPools["east-west"].ipv4.prefix == "100.96.10.0/24"
  and (.sites.esp.hetz.overlayAddressPools["wg-host128-egress"].ipv4.prefix
       != .sites.esp.hetz.overlayAddressPools["wg-routed64"].ipv4.prefix)
' "${compiled_json}" >/dev/null || fail "Overlay IPAM: expected segmented, distinct pools per overlay"

echo "PASS: Overlay address pools are segmented and distinct"

# ============================================================
# Seeded Negative 1: Overlay on non-core node
# ============================================================
echo ""
echo "--- Seeded Negative 1: Overlay terminateOn non-core ---"

expect_compile_failure \
  "overlay-on-non-core" \
  "${ROOT}/tests/negative/overlay-on-non-core.nix" \
  "E_OVERLAY_TERMINATE_NON_CORE"

# ============================================================
# Seeded Negative 2: Multiple cores, no terminateOn (ambiguous)
# ============================================================
echo ""
echo "--- Seeded Negative 2: Ambiguous core (multiple cores, no terminateOn) ---"

cat > "${tmp_dir}/ambiguous-core.nix" <<'AMBIGUOUS'
{
  badsite = {
    pools = {
      p2p.ipv4 = "10.10.0.0/24";
      loopback.ipv4 = "10.19.0.0/24";
    };
    ownership.prefixes = [
      { kind = "tenant"; name = "client"; ipv4 = "10.20.10.0/24"; }
    ];
    communicationContract = {
      trafficTypes = [
        { name = "wireguard"; match = [{ proto = "udp"; family = "any"; dports = [ 51820 ]; }]; }
      ];
      services = [ ];
      relations = [
        {
          id = "allow-client-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "allow-wg-underlay";
          priority = 110;
          from = { kind = "external"; name = "wg-host128-egress"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "wireguard";
          action = "allow";
        }
      ];
    };
    transport.overlays = [
      {
        name = "wg-host128-egress";
        mustTraverse = [ "policy" ];
        underlayAccess = { kind = "tenant"; name = "client"; };
        underlayTrafficTypes = [ "wireguard" ];
      }
    ];
    topology = {
      nodes = {
        core-wan = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
        core-nebula = {
          role = "core";
          uplinks.east-west.ipv4 = [ "100.96.0.0/24" ];
        };
        upstream.role = "upstream-selector";
        policy.role = "policy";
        downstream.role = "downstream-selector";
        access = {
          role = "access";
          attachments = [{ kind = "tenant"; name = "client"; }];
        };
      };
      links = [
        [ "core-wan" "upstream" ]
        [ "core-nebula" "upstream" ]
        [ "upstream" "policy" ]
        [ "policy" "downstream" ]
        [ "downstream" "access" ]
      ];
    };
  };
}
AMBIGUOUS

expect_compile_failure \
  "ambiguous-overlay-core" \
  "${tmp_dir}/ambiguous-core.nix" \
  "E_OVERLAY_AMBIGUOUS_CORE"

# ============================================================
# Seeded Negative 3: Overlay terminateOn unknown node
# ============================================================
echo ""
echo "--- Seeded Negative 3: Overlay terminateOn unknown node ---"

cat > "${tmp_dir}/unknown-termination.nix" <<'UNKNOWNTERM'
{
  badsite = {
    pools = {
      p2p.ipv4 = "10.10.0.0/24";
      loopback.ipv4 = "10.19.0.0/24";
    };
    ownership.prefixes = [
      { kind = "tenant"; name = "client"; ipv4 = "10.20.10.0/24"; }
    ];
    communicationContract = {
      trafficTypes = [
        { name = "wireguard"; match = [{ proto = "udp"; family = "any"; dports = [ 51820 ]; }]; }
      ];
      services = [ ];
      relations = [
        {
          id = "allow-client-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "allow-wg-underlay";
          priority = 110;
          from = { kind = "external"; name = "wg-host128-egress"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "wireguard";
          action = "allow";
        }
      ];
    };
    transport.overlays = [
      {
        name = "wg-host128-egress";
        terminateOn = "nonexistent-core";
        mustTraverse = [ "policy" ];
        underlayAccess = { kind = "tenant"; name = "client"; };
        underlayTrafficTypes = [ "wireguard" ];
      }
    ];
    topology = {
      nodes = {
        core = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
        upstream.role = "upstream-selector";
        policy.role = "policy";
        downstream.role = "downstream-selector";
        access = {
          role = "access";
          attachments = [{ kind = "tenant"; name = "client"; }];
        };
      };
      links = [
        [ "core" "upstream" ]
        [ "upstream" "policy" ]
        [ "policy" "downstream" ]
        [ "downstream" "access" ]
      ];
    };
  };
}
UNKNOWNTERM

expect_compile_failure \
  "overlay-unknown-termination" \
  "${tmp_dir}/unknown-termination.nix" \
  "E_OVERLAY_UNKNOWN_TERMINATION"

# ============================================================
# Final verdict
# ============================================================
echo ""
if [[ "${all_passed}" == "true" ]]; then
  echo "PASS test-sat-wireguard-host128-core-split"
else
  echo "FAIL test-sat-wireguard-host128-core-split" >&2
  exit 1
fi
