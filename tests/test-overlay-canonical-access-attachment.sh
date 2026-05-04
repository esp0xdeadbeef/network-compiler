#!/usr/bin/env bash
set -euo pipefail

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

input_file="${tmp_dir}/overlay-input.nix"
output_json="${tmp_dir}/compiled.json"

cat > "$input_file" <<'EOF'
{
  acme = {
    ams = {
      pools = {
        p2p = {
          ipv4 = "10.10.0.0/24";
          ipv6 = "fd42:dead:beef:1000::/118";
        };
        loopback = {
          ipv4 = "10.19.0.0/24";
          ipv6 = "fd42:dead:beef:1900::/118";
        };
      };

      ownership.prefixes = [
        {
          kind = "tenant";
          name = "mgmt";
          ipv4 = "10.20.10.0/24";
          ipv6 = "fd42:dead:beef:10::/64";
        }
      ];

      communicationContract = {
        trafficTypes = [ ];
        services = [ ];
        relations = [
          {
            id = "allow-mgmt-to-east-west";
            priority = 100;
            from = { kind = "tenant"; name = "mgmt"; };
            to = { kind = "external"; name = "east-west"; };
            trafficType = "any";
            action = "allow";
          }
        ];
      };

      transport.overlays = [
        {
          name = "east-west";
          peerSite = "acme.remote";
          terminateOn = "core-overlay";
          mustTraverse = [ "policy" ];
        }
      ];

      topology = {
        nodes = {
          core-wan = {
            role = "core";
            uplinks.wan = {
              ipv4 = [ "0.0.0.0/0" ];
              ipv6 = [ "::/0" ];
            };
          };
          core-overlay = {
            role = "core";
            uplinks.east-west = {
              ipv4 = [ "100.96.20.0/24" ];
              ipv6 = [ "fd42:dead:beef:20::/64" ];
            };
          };
          upstream = { role = "upstream-selector"; };
          policy = { role = "policy"; };
          downstream = { role = "downstream-selector"; };
          access = {
            role = "access";
            attachments = [
              { kind = "tenant"; name = "mgmt"; }
            ];
          };
        };

        links = [
          [ "core-wan" "upstream" ]
          [ "core-overlay" "upstream" ]
          [ "upstream" "policy" ]
          [ "policy" "downstream" ]
          [ "downstream" "access" ]
        ];
      };
    };
  };
}
EOF

nix run "$ROOT#compile" -- "$input_file" > "$output_json"

if jq -e '
  .sites.acme.ams.overlayAttachments."east-west".canonicalPath
    == [ "core-wan", "upstream", "policy", "downstream", "access", "overlay:east-west" ]
  and .sites.acme.ams.overlayAttachments."east-west".attachAfterStage == "access"
  and .sites.acme.ams.overlayAttachments."east-west".terminatesOn == [ "core-overlay" ]
' "$output_json" >/dev/null; then
  echo "PASS overlay-canonical-access-attachment"
else
  cat >&2 <<'EOF'
FATAL network-compiler overlay canonical access attachment contract is not implemented yet.

This red failure may be removed only after network-compiler emits provider-neutral
overlay attachment semantics for every declared overlay domain:

  wan/external -> upstream-selector -> policy -> downstream-selector -> access -> overlay

Required compiler responsibilities:

  - reject overlay domains that bypass the canonical staged path
  - require an explicit owning access attachment for every overlay domain
  - require policy relations before overlay reachability exists
  - emit enough semantic data for network-forwarding-model to derive deterministic
    access-to-overlay p2p/lane structure without reading inventory or renderer names

Do not remove this test by teaching the compiler about SOPS or realization
inventory. The compiler input remains one semantic attrset/path.
EOF
  exit 1
fi
