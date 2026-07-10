#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-610-HDS-010-SDS-010-SMS-040
# GAMP-SCOPE: software-module-test
# SMS-040: Broad Discovery Flooding Denial
# Tests seeded negatives: BROAD_FLOODING_DENIED, REVERSE_DISCOVERY_DENIED

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

good_input="${tmp_dir}/fs610-sms040-good.nix"

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
      profileManifest = {
        accessSpaces = {
          client.localServiceDiscovery = "media-requester";
          streaming.localServiceDiscovery = "media-responder";
        };
        tenantAccessMatrix = [
          {
            scope = "client";
            discoveryExports = [ "svc1" ];
            allowedServices = [ "svc1" ];
          }
          {
            scope = "streaming";
            discoveryExports = [ ];
            allowedServices = [ ];
          }
        ];
        sharedServiceMatrix = [
          {
            requesterScopes = [ "client" ];
            responderScope = "streaming";
            serviceClass = "media-receiver";
            service = "svc1";
            discovery = {
              protocol = "mdns";
              direction = "unidirectional";
            };
            payload = {
              protocol = "tcp";
              ports = [ 8008 ];
              direction = "unidirectional";
              returnBehavior = "stateful-return";
            };
          }
        ];
      };
      communicationContract = {
        relations = [
          {
            id = "r1";
            action = "allow";
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "tenant"; name = "streaming"; };
            trafficType = "tcp8008";
          }
          {
            id = "r2";
            action = "allow";
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "external"; uplinks = [ "internet-vlan4" ]; };
            trafficType = "any";
            priority = 100;
          }
        ];
        services = [
          {
            name = "svc1";
            trafficType = "tcp8008";
            servicePolicy = {
              requesterScopes = [ "client" ];
              responderScope = "streaming";
              serviceClass = "media-receiver";
              discovery = {
                protocol = "mdns";
                direction = "unidirectional";
                advertisedServices = [ "_test._tcp" ];
              };
              payload = {
                protocol = "tcp";
                ports = [ 8008 ];
                direction = "unidirectional";
                returnBehavior = "bidirectional";
              };
              management = { allowed = false; };
              reverseInitiation = { allowed = false; };
              deniedPaths = [
                { sourceScope = "streaming"; destinationScope = "client"; reason = "test"; }
              ];
              exposureClass = "shared-local";
              authenticationBoundary = "none";
              cloudDependency = "none";
            };
          }
        ];
        trafficTypes = [
          { name = "tcp8008"; match = [ { family = "any"; proto = "tcp"; to = "8008"; } ]; }
        ];
      };
      topology = {
        links = [
          [ "client-edge" "downstream-selector" ]
          [ "downstream-selector" "policy" ]
          [ "policy" "upstream-selector" ]
          [ "upstream-selector" "core" ]
        ];
        nodes = {
          "client-edge" = {
            role = "access";
            attachments = [ { kind = "tenant"; name = "client"; } ];
          };
          "downstream-selector" = { role = "downstream-selector"; };
          policy = { role = "policy"; };
          "upstream-selector" = { role = "upstream-selector"; };
          core = {
            role = "core";
            external = "internet-vlan4";
            uplinks = {
              "internet-vlan4" = {
                ipv4 = [ "0.0.0.0/0" ];
                ipv6 = [ "::/0" ];
              };
            };
          };
        };
      };
    };
  };
}
NIX

fail() {
  echo "FAIL fs610-sms040: $*" >&2
  exit 1
}

# Verify good input compiles
nix run "$ROOT#compile" -- "$good_input" --json >/dev/null 2>/dev/null || fail "good input failed to compile"

# SN1: relayOrProxyBoundary = "multicast-flood" -> BROAD_FLOODING_DENIED
# Replace "svc1" in discoveryExports with attrset having relayOrProxyBoundary: "multicast-flood"
sed 's|discoveryExports = \[ "svc1" \]|discoveryExports = [ { service = "svc1"; relayOrProxyBoundary = "multicast-flood"; } ]|' \
  "$good_input" >"${tmp_dir}/sn1-broad-flooding.nix"
set +e
nix run "$ROOT#compile" -- "${tmp_dir}/sn1-broad-flooding.nix" 2>"${tmp_dir}/sn1-broad-flooding.err" >/dev/null
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  fail "SN1 broad flooding unexpectedly compiled"
fi
grep -q "BROAD_FLOODING_DENIED" "${tmp_dir}/sn1-broad-flooding.err" || fail "SN1 missing BROAD_FLOODING_DENIED diagnostic"
echo "SN1 BROAD_FLOODING_DENIED: PASS"

# SN2: reverseDiscovery = true without reversePathRelationship -> REVERSE_DISCOVERY_DENIED
sed 's|discoveryExports = \[ "svc1" \]|discoveryExports = [ { service = "svc1"; reverseDiscovery = true; } ]|' \
  "$good_input" >"${tmp_dir}/sn2-reverse-discovery.nix"
set +e
nix run "$ROOT#compile" -- "${tmp_dir}/sn2-reverse-discovery.nix" 2>"${tmp_dir}/sn2-reverse-discovery.err" >/dev/null
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  fail "SN2 reverse discovery unexpectedly compiled"
fi
grep -q "REVERSE_DISCOVERY_DENIED" "${tmp_dir}/sn2-reverse-discovery.err" || fail "SN2 missing REVERSE_DISCOVERY_DENIED diagnostic"
echo "SN2 REVERSE_DISCOVERY_DENIED: PASS"

# SN2_positive: reverseDiscovery = true with reversePathRelationship -> SHOULD PASS
sed 's|discoveryExports = \[ "svc1" \]|discoveryExports = [ { service = "svc1"; reverseDiscovery = true; reversePathRelationship = { authorized = true; }; } ]|' \
  "$good_input" >"${tmp_dir}/sn2-positive-reverse-path.nix"
nix run "$ROOT#compile" -- "${tmp_dir}/sn2-positive-reverse-path.nix" --json >/dev/null 2>/dev/null || fail "SN2_positive with reversePathRelationship unexpectedly failed"
echo "SN2_positive (reverseDiscovery with reversePathRelationship): PASS"

echo "PASS FS-610-HDS-010-SDS-010-SMS-040"
