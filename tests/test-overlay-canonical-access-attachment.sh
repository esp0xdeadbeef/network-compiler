#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-COMP-OVERLAY-ACCESS-001
# GAMP-ID: FS-030-HDS-010-SDS-030-SMS-010
# GAMP-SCOPE: software-module-test

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
        {
          kind = "tenant";
          name = "client";
          ipv4 = "10.20.20.0/24";
          ipv6 = "fd42:dead:beef:20::/64";
        }
      ];

      communicationContract = {
        trafficTypes = [
          {
            name = "nebula";
            match = [
              { proto = "udp"; dports = [ 4242 ]; family = "any"; }
            ];
          }
        ];
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
          {
            id = "allow-client-underlay-access-to-wan";
            priority = 105;
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
          peerSite = "acme.remote";
          terminateOn = "core-overlay";
          underlayAccess = { kind = "tenant"; name = "client"; };
          underlayTrafficTypes = [ "nebula" ];
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
            attachments = [
              { kind = "tenant"; name = "client"; }
            ];
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
          access-client = {
            role = "access";
            attachments = [
              { kind = "tenant"; name = "client"; }
            ];
          };
        };

        links = [
          [ "core-wan" "upstream" ]
          [ "upstream" "policy" ]
          [ "policy" "downstream" ]
          [ "downstream" "access" ]
          [ "downstream" "access-client" ]
        ];
      };
    };
  };
}
EOF

nix run "$ROOT#compile" -- "$input_file" > "$output_json"

if jq -e '
  .sites.acme.ams.overlayAttachments."east-west".canonicalPath
    == [ "core-wan", "upstream", "policy", "downstream", "access-client", "overlay:east-west" ]
  and .sites.acme.ams.overlayAttachments."east-west".attachAfterStage == "access"
  and .sites.acme.ams.overlayAttachments."east-west".accessNodes == [ "access-client" ]
  and .sites.acme.ams.overlayAttachments."east-west".terminatesOn == [ "core-overlay" ]
  and ([
    .sites.acme.ams.communicationContract.relations[]?
    | select((.from.kind // null) == "tenant")
    | select((.from.name // null) == "client")
    | select((.to.kind // null) == "external")
    | select((.to.name // null) == "east-west")
  ] == [])
  and ([.sites.acme.ams.topology.links[]? | select(.a == "core-overlay" or .b == "core-overlay")] == [])
  and [
    .sites.acme.ams.trafficPaths[]
    | select(.relationId == "allow-east-west-underlay-to-wan")
    | .nodePath
  ] == [[ "core-overlay", "access-client", "downstream", "policy", "upstream", "core-wan" ]]
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
  - require the selected underlay access tenant to have modeled egress to the
    target WAN external before using it for daemon/bootstrap underlay
  - emit enough semantic data for network-forwarding-model to derive deterministic
    access-to-overlay p2p/lane structure without reading inventory or renderer names

Do not remove this test by teaching the compiler about SOPS or realization
inventory. The compiler input remains one semantic attrset/path.
EOF
  exit 1
fi

bad_input_file="${tmp_dir}/overlay-underlay-no-wan-egress.nix"
cat > "$bad_input_file" <<'EOF'
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
        access-hostile = { role = "access"; attachments = [ { kind = "tenant"; name = "hostile"; } ]; };
        access-client = { role = "access"; attachments = [ { kind = "tenant"; name = "client"; } ]; };
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

set +e
bad_output="$(nix run "$ROOT#compile" -- "$bad_input_file" 2>&1)"
bad_rc=$?
set -e

if [[ "$bad_rc" -eq 0 ]]; then
  echo "FAIL overlay-canonical-access-attachment: underlayAccess without WAN egress compiled" >&2
  exit 1
fi

if ! grep -q "E_OVERLAY_UNDERLAY_ACCESS_WAN_EGRESS_REQUIRED" <<<"$bad_output"; then
  echo "FAIL overlay-canonical-access-attachment: missing underlay WAN egress error" >&2
  printf '%s\n' "$bad_output" >&2
  exit 1
fi
