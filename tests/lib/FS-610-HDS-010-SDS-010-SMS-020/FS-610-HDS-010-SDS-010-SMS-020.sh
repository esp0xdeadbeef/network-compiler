#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-610-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
# SMS-020: Discovery Boundary Decision Separation
# Tests seeded negatives: DISCOVERY_PAYLOAD_AUTHORIZATION_LEAK, DISCOVERY_MANAGEMENT_AUTHORIZATION_LEAK, DISCOVERY_REVERSE_DISCOVERY_AUTHORIZATION_LEAK

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

good_input="${tmp_dir}/fs610-sms020-good.nix"

cat >"$good_input" <<'NIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = { p2p.ipv4 = "10.10.0.0/24"; loopback.ipv4 = "10.19.0.0/24"; };
      ownership = {
        prefixes = [
          { kind = "tenant"; name = "client"; ipv4 = "10.20.20.0/24"; }
          { kind = "tenant"; name = "streaming"; ipv4 = "10.20.50.0/24"; }
        ];
      };
      communicationContract = {
        relations = [
          { id = "r1"; action = "allow"; from = { kind = "tenant"; name = "client"; }; to = { kind = "tenant"; name = "streaming"; }; trafficType = "tcp8008"; }
          { id = "r2"; action = "allow"; from = { kind = "tenant"; name = "client"; }; to = { kind = "external"; uplinks = [ "internet-vlan4" ]; }; trafficType = "any"; priority = 100; }
        ];
        services = [
          { name = "svc1"; trafficType = "tcp8008"; servicePolicy = {
            requesterScopes = [ "client" ]; responderScope = "streaming"; serviceClass = "media-cast";
            discovery = { protocol = "mdns"; direction = "unidirectional"; advertisedServices = [ "_test._tcp" ]; };
            payload = { protocol = "tcp"; ports = [ 8008 ]; direction = "unidirectional"; returnBehavior = "bidirectional"; };
            management = { allowed = false; }; reverseInitiation = { allowed = false; };
            deniedPaths = [ { sourceScope = "streaming"; destinationScope = "client"; reason = "test"; } ];
            exposureClass = "shared-local"; authenticationBoundary = "none"; cloudDependency = "none";
          };}
        ];
        trafficTypes = [ { name = "tcp8008"; match = [ { family = "any"; proto = "tcp"; to = "8008"; } ]; } ];
      };
      topology = {
        links = [ [ "client-edge" "downstream-selector" ] [ "downstream-selector" "policy" ] [ "policy" "upstream-selector" ] [ "upstream-selector" "core" ] ];
        nodes = {
          "client-edge" = { role = "access"; attachments = [ { kind = "tenant"; name = "client"; } ]; };
          "downstream-selector" = { role = "downstream-selector"; };
          policy = { role = "policy"; };
          "upstream-selector" = { role = "upstream-selector"; };
          core = { role = "core"; external = "internet-vlan4"; uplinks = { "internet-vlan4" = { ipv4 = [ "0.0.0.0/0" ]; ipv6 = [ "::/0" ]; }; }; };
        };
      };
    };
  };
}
NIX

fail() {
  echo "FAIL fs610-sms020: $*" >&2
  exit 1
}

# Verify good input compiles
nix run "$ROOT#compile" -- "$good_input" --json >/dev/null 2>/dev/null || fail "good input failed to compile"

# SN1: inferPayloadFromDiscovery = true -> DISCOVERY_PAYLOAD_AUTHORIZATION_LEAK
sed 's/cloudDependency = "none";/cloudDependency = "none"; inferPayloadFromDiscovery = true;/' \
  "$good_input" >"${tmp_dir}/sn1-payload-leak.nix"
set +e
nix run "$ROOT#compile" -- "${tmp_dir}/sn1-payload-leak.nix" 2>"${tmp_dir}/sn1-payload-leak.err" >/dev/null
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  fail "SN1 inferPayloadFromDiscovery unexpectedly compiled"
fi
grep -q "DISCOVERY_PAYLOAD_AUTHORIZATION_LEAK" "${tmp_dir}/sn1-payload-leak.err" || fail "SN1 missing DISCOVERY_PAYLOAD_AUTHORIZATION_LEAK diagnostic"

# SN2: inferManagementFromDiscovery = true -> DISCOVERY_MANAGEMENT_AUTHORIZATION_LEAK
sed 's/cloudDependency = "none";/cloudDependency = "none"; inferManagementFromDiscovery = true;/' \
  "$good_input" >"${tmp_dir}/sn2-management-leak.nix"
set +e
nix run "$ROOT#compile" -- "${tmp_dir}/sn2-management-leak.nix" 2>"${tmp_dir}/sn2-management-leak.err" >/dev/null
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  fail "SN2 inferManagementFromDiscovery unexpectedly compiled"
fi
grep -q "DISCOVERY_MANAGEMENT_AUTHORIZATION_LEAK" "${tmp_dir}/sn2-management-leak.err" || fail "SN2 missing DISCOVERY_MANAGEMENT_AUTHORIZATION_LEAK diagnostic"

# SN3: inferReverseInitiationFromDiscovery = true -> DISCOVERY_REVERSE_DISCOVERY_AUTHORIZATION_LEAK
sed 's/cloudDependency = "none";/cloudDependency = "none"; inferReverseInitiationFromDiscovery = true;/' \
  "$good_input" >"${tmp_dir}/sn3-reverse-leak.nix"
set +e
nix run "$ROOT#compile" -- "${tmp_dir}/sn3-reverse-leak.nix" 2>"${tmp_dir}/sn3-reverse-leak.err" >/dev/null
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  fail "SN3 inferReverseInitiationFromDiscovery unexpectedly compiled"
fi
grep -q "DISCOVERY_REVERSE_DISCOVERY_AUTHORIZATION_LEAK" "${tmp_dir}/sn3-reverse-leak.err" || fail "SN3 missing DISCOVERY_REVERSE_DISCOVERY_AUTHORIZATION_LEAK diagnostic"

echo "PASS FS-610-HDS-010-SDS-010-SMS-020"
