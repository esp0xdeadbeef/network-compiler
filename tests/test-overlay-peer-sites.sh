#!/usr/bin/env bash
set -euo pipefail

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

input_file="${tmp_dir}/input.nix"
output_json="${tmp_dir}/compiled.json"

cat >"$input_file" <<'EOF'
{
  acme.ams = {
    pools.p2p.ipv4 = "10.10.0.0/24";
    pools.loopback.ipv4 = "10.19.0.0/24";
    ownership.prefixes = [
      { kind = "tenant"; name = "lan"; ipv4 = "10.20.10.0/24"; }
    ];
    communicationContract.relations = [
      {
        id = "allow-lan-east-west";
        priority = 100;
        from = { kind = "tenant"; name = "lan"; };
        to = { kind = "external"; name = "east-west"; };
        trafficType = "any";
        action = "allow";
      }
    ];
    transport.overlays = [
      {
        name = "east-west";
        peerSites = [ "acme.remote-a" "acme.remote-b" ];
        terminateOn = "core-overlay";
        mustTraverse = [ "policy" ];
      }
    ];
    topology.nodes = {
      core-overlay.role = "core";
      core-overlay.uplinks.east-west.ipv4 = [ "100.96.0.0/24" ];
      upstream.role = "upstream-selector";
      policy.role = "policy";
      downstream.role = "downstream-selector";
      access.role = "access";
      access.attachments = [ { kind = "tenant"; name = "lan"; } ];
    };
    topology.links = [
      [ "core-overlay" "upstream" ]
      [ "upstream" "policy" ]
      [ "policy" "downstream" ]
      [ "downstream" "access" ]
    ];
  };

  acme.remote-a = {
    pools.p2p.ipv4 = "10.30.0.0/24";
    pools.loopback.ipv4 = "10.39.0.0/24";
    ownership.prefixes = [
      { kind = "tenant"; name = "remote-a"; ipv4 = "10.40.10.0/24"; }
    ];
    communicationContract.relations = [
      { id = "allow-remote-a"; priority = 100; from = { kind = "tenant"; name = "remote-a"; }; to = { kind = "external"; name = "east-west"; }; trafficType = "any"; action = "allow"; }
    ];
    transport.overlays = [
      { name = "east-west"; peerSite = "acme.ams"; terminateOn = "core-overlay"; mustTraverse = [ "policy" ]; }
    ];
    topology.nodes = {
      core-overlay.role = "core";
      core-overlay.uplinks.east-west.ipv4 = [ "100.96.0.0/24" ];
      upstream.role = "upstream-selector";
      policy.role = "policy";
      downstream.role = "downstream-selector";
      access.role = "access";
      access.attachments = [ { kind = "tenant"; name = "remote-a"; } ];
    };
    topology.links = [ [ "core-overlay" "upstream" ] [ "upstream" "policy" ] [ "policy" "downstream" ] [ "downstream" "access" ] ];
  };

  acme.remote-b = {
    pools.p2p.ipv4 = "10.50.0.0/24";
    pools.loopback.ipv4 = "10.59.0.0/24";
    ownership.prefixes = [
      { kind = "tenant"; name = "remote-b"; ipv4 = "10.60.10.0/24"; }
    ];
    communicationContract.relations = [
      { id = "allow-remote-b"; priority = 100; from = { kind = "tenant"; name = "remote-b"; }; to = { kind = "external"; name = "east-west"; }; trafficType = "any"; action = "allow"; }
    ];
    transport.overlays = [
      { name = "east-west"; peerSite = "acme.ams"; terminateOn = "core-overlay"; mustTraverse = [ "policy" ]; }
    ];
    topology.nodes = {
      core-overlay.role = "core";
      core-overlay.uplinks.east-west.ipv4 = [ "100.96.0.0/24" ];
      upstream.role = "upstream-selector";
      policy.role = "policy";
      downstream.role = "downstream-selector";
      access.role = "access";
      access.attachments = [ { kind = "tenant"; name = "remote-b"; } ];
    };
    topology.links = [ [ "core-overlay" "upstream" ] [ "upstream" "policy" ] [ "policy" "downstream" ] [ "downstream" "access" ] ];
  };
}
EOF

nix run "$ROOT#compile" -- "$input_file" >"$output_json"

if jq -e '
  .meta.provenance.originalInputs.acme.ams.transport.overlays[0].peerSites
    == [ "acme.remote-a", "acme.remote-b" ]
  and .sites.acme.ams.overlayAttachments."east-west".canonicalPath
    == [ "core-overlay", "upstream", "policy", "downstream", "access", "overlay:east-west" ]
  and .sites.acme.ams.overlayAttachments."east-west".terminatesOn == [ "core-overlay" ]
' "$output_json" >/dev/null; then
  echo "PASS overlay-peer-sites"
else
  echo "FAIL overlay-peer-sites: compiler did not accept multi-peer overlay intent" >&2
  exit 1
fi
