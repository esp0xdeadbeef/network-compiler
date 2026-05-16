#!/usr/bin/env bash
set -euo pipefail

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

input_file="${tmp_dir}/input.nix"
output_json="${tmp_dir}/compiled.json"

cat >"$input_file" <<'EOF'
{
  esp.hetz = {
    pools.p2p.ipv4 = "10.80.0.0/24";
    pools.loopback.ipv4 = "10.89.0.0/24";
    ownership.prefixes = [
      { kind = "tenant"; name = "client"; ipv4 = "10.90.20.0/24"; }
    ];
    communicationContract.trafficTypes = [
      {
        name = "nebula";
        match = [
          { proto = "udp"; dports = [ 4242 ]; family = "any"; }
        ];
      }
    ];
    communicationContract.relations = [
      {
        id = "allow-client-to-wan";
        priority = 90;
        from = { kind = "tenant"; name = "client"; };
        to = { kind = "external"; name = "wan"; };
        trafficType = "any";
        action = "allow";
      }
      {
        id = "allow-overlay-ingress-to-wan";
        priority = 100;
        from = { kind = "external"; name = "east-west"; };
        to = { kind = "external"; name = "wan"; };
        trafficType = "any";
        action = "allow";
      }
      {
        id = "allow-overlay-underlay-to-wan";
        priority = 110;
        from = { kind = "external"; name = "east-west"; };
        to = { kind = "external"; name = "wan"; };
        trafficType = "nebula";
        action = "allow";
      }
    ];
    transport.overlays = [
      {
        name = "east-west";
        peerSites = [ "esp.nixos" "esp.clab" ];
        terminateOn = "hetz-router-nebula-core";
        mustTraverse = [ "policy" ];
      }
    ];
    topology.nodes = {
      hetz-router-core.role = "core";
      hetz-router-core.uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
      hetz-router-nebula-core.role = "core";
      hetz-router-nebula-core.uplinks.east-west.ipv4 = [ "10.20.70.0/24" ];
      hetz-router-upstream.role = "upstream-selector";
      hetz-router-policy.role = "policy";
      hetz-router-downstream.role = "downstream-selector";
      hetz-router-access-client.role = "access";
      hetz-router-access-client.attachments = [ { kind = "tenant"; name = "client"; } ];
    };
    topology.links = [
      [ "hetz-router-core" "hetz-router-upstream" ]
      [ "hetz-router-nebula-core" "hetz-router-upstream" ]
      [ "hetz-router-upstream" "hetz-router-policy" ]
      [ "hetz-router-policy" "hetz-router-downstream" ]
      [ "hetz-router-downstream" "hetz-router-access-client" ]
    ];
  };
}
EOF

nix run "$ROOT#compile" -- "$input_file" >"$output_json"

if jq -e '
  (
    [.sites.esp.hetz.relations[]
      | select(.source.id == "allow-overlay-ingress-to-wan")
      | select(.from == { kind: "external", name: "east-west" })
      | select(.to == { kind: "external", name: "wan" })
    ] | length == 1
  )
  and (
    .sites.esp.hetz.trafficPaths[]
    | select(.relationId == "allow-overlay-ingress-to-wan")
    | select(.stagePath == [
        "core",
        "upstream-selector",
        "policy",
        "upstream-selector",
        "core"
      ])
    | select(.nodePath == [
        "hetz-router-nebula-core",
        "hetz-router-upstream",
        "hetz-router-policy",
        "hetz-router-upstream",
        "hetz-router-core"
      ])
    | select(.corePathNodes == [
        "hetz-router-nebula-core",
        "hetz-router-core"
      ])
  )
' "$output_json" >/dev/null; then
  echo "PASS overlay-ingress-policy-reference"
else
  echo "FAIL overlay-ingress-policy-reference" >&2
  exit 1
fi
