#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-COMP-OVERLAY-ADDRESS-POOL-001
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

input_file="${tmp_dir}/input.nix"
output_json="${tmp_dir}/compiled.json"

cat >"$input_file" <<'EOF'
{
  acme.ams = {
    pools = {
      p2p.ipv4 = "10.10.0.0/24";
      loopback.ipv4 = "10.19.0.0/24";
      overlay = {
        ipv4 = { prefix = "100.96.10.0/24"; perNodePrefixLength = 32; offsetStart = 10; };
        ipv6 = { prefix = "fd42:dead:beef:ee::/64"; perNodePrefixLength = 128; offsetStart = 10; };
      };
    };
    ownership.prefixes = [
      { kind = "tenant"; name = "lan"; ipv4 = "10.20.10.0/24"; }
    ];
    communicationContract.trafficTypes = [
      { name = "nebula"; match = [ { proto = "udp"; dports = [ 4242 ]; family = "any"; } ]; }
    ];
    communicationContract.services = [ ];
    communicationContract.relations = [
      { id = "allow-lan-east-west"; priority = 100; from = { kind = "tenant"; name = "lan"; }; to = { kind = "external"; name = "east-west"; }; trafficType = "any"; action = "allow"; }
      { id = "allow-lan-nebula-underlay-to-wan"; priority = 105; from = { kind = "tenant"; name = "lan"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "nebula"; action = "allow"; }
      { id = "allow-east-west-underlay"; priority = 110; from = { kind = "external"; name = "east-west"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "nebula"; action = "allow"; }
    ];
    transport.overlays = [
      { name = "east-west"; terminateOn = "core-nebula"; underlayAccess = { kind = "tenant"; name = "lan"; }; underlayTrafficTypes = [ "nebula" ]; mustTraverse = [ "policy" ]; }
    ];
    topology.nodes = {
      core-wan = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; };
      core-nebula = { role = "core"; uplinks.east-west.ipv4 = [ "0.0.0.0/0" ]; };
      upstream.role = "upstream-selector";
      policy.role = "policy";
      downstream.role = "downstream-selector";
      access = { role = "access"; attachments = [ { kind = "tenant"; name = "lan"; } ]; };
    };
    topology.links = [
      [ "core-wan" "upstream" ]
      [ "core-nebula" "upstream" ]
      [ "upstream" "policy" ]
      [ "policy" "downstream" ]
      [ "downstream" "access" ]
    ];
  };
}
EOF

nix run "$ROOT#compile" -- "$input_file" >"$output_json"

jq -e '
  .sites.acme.ams.overlayAddressPools."east-west".ipv4.prefix == "100.96.10.0/24"
  and .sites.acme.ams.overlayAddressPools."east-west".ipv4.perNodePrefixLength == 32
  and .sites.acme.ams.overlayAddressPools."east-west".ipv4.offsetStart == 10
  and .sites.acme.ams.overlayAddressPools."east-west".ipv6.prefix == "fd42:dead:beef:ee::/64"
  and .sites.acme.ams.overlayAddressPools."east-west".ipv6.perNodePrefixLength == 128
  and .sites.acme.ams.overlayAddressPools."east-west".ipv6.offsetStart == 10
' "$output_json" >/dev/null

echo "PASS overlay-address-pools"
