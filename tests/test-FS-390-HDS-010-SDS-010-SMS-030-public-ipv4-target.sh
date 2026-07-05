#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-390-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: compiler construction check for public IPv4 policy targets

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

input_nix="${tmp_dir}/public-ipv4-target.nix"
output_json="${tmp_dir}/public-ipv4-target.json"

cat >"${input_nix}" <<'NIX'
{
  mini-smt = {
    "FS-390-HDS-010-SDS-010-SMS-030" = {
      pools = {
        p2p.ipv4 = "10.30.255.0/24";
        loopback.ipv4 = "10.30.0.0/24";
      };

      ownership = {
        prefixes = [
          {
            kind = "tenant";
            name = "client";
            ipv4 = "10.30.10.0/24";
            publicIpv4 = "203.0.113.100/32";
          }
        ];
      };

      communicationContract = {
        interfaceTags = {
          external-testnet = "testnet";
          tenant-client = "client";
        };
        trafficTypes = [
          {
            name = "any";
            match = [ { family = "any"; proto = "any"; } ];
          }
        ];
        services = [ ];
        relations = [
          {
            id = "FS-390-HDS-010-SDS-010-SMS-030__client-to-testnet";
            priority = 100;
            action = "allow";
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "external"; uplinks = [ "testnet" ]; };
            trafficType = "any";
          }
          {
            id = "FS-390-HDS-010-SDS-010-SMS-030__client-to-owned-public-via-broad-wan";
            priority = 110;
            action = "allow";
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "public-ipv4"; ipv4 = "203.0.113.100"; };
            trafficType = "any";
          }
        ];
      };

      topology.nodes = {
        client-edge = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
        };
        downstream-selector.role = "downstream-selector";
        policy.role = "policy";
        upstream-selector.role = "upstream-selector";
        vlan4-client-dhcp-slaac = {
          role = "core";
          uplinks.testnet.ipv4 = [ "0.0.0.0/0" ];
        };
      };

      topology.links = [
        [ "client-edge" "downstream-selector" ]
        [ "downstream-selector" "policy" ]
        [ "policy" "upstream-selector" ]
        [ "upstream-selector" "vlan4-client-dhcp-slaac" ]
      ];
    };
  };
}
NIX

nix run --no-warn-dirty "${ROOT}#compile" -- "${input_nix}" >"${output_json}"

jq -e --arg trace "FS-390-HDS-010-SDS-010-SMS-030" '
  .sites."mini-smt"[$trace] as $site
  | ([
      $site.relations[]
      | select(.source.id == ($trace + "__client-to-owned-public-via-broad-wan"))
      | select(.to == { kind: "public-ipv4", ipv4: "203.0.113.100" })
    ] | length == 1)
    and ([
      $site.trafficPaths[]
      | select(.relationId == ($trace + "__client-to-owned-public-via-broad-wan"))
      | select(.destination == { kind: "public-ipv4", ipv4: "203.0.113.100" })
      | select(.stagePath == [
          "access",
          "downstream-selector",
          "policy",
          "upstream-selector",
          "core"
        ])
      | select(.nodePath == [
          "client-edge",
          "downstream-selector",
          "policy",
          "upstream-selector",
          "vlan4-client-dhcp-slaac"
        ])
    ] | length == 1)
' "${output_json}" >/dev/null

echo "PASS FS-390-HDS-010-SDS-010-SMS-030 public IPv4 compiler target"
