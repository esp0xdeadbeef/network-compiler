#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-COMP-WILDCARD-TARGET-001
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

input_file="${tmp_dir}/wildcard-target.nix"
output_json="${tmp_dir}/wildcard-target.json"

cat >"$input_file" <<'NIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };

      ownership.prefixes = [
        { kind = "tenant"; name = "admin"; ipv4 = "10.20.10.0/24"; }
        { kind = "tenant"; name = "client"; ipv4 = "10.20.20.0/24"; }
        { kind = "tenant"; name = "mgmt"; ipv4 = "10.20.30.0/24"; }
      ];

      communicationContract = {
        trafficTypes = [
          { name = "icmp"; match = [ { proto = "icmp"; family = "any"; } ]; }
        ];
        services = [ ];
        relations = [
          {
            id = "allow-client-icmp-anywhere";
            priority = 10;
            from = { kind = "tenant"; name = "client"; };
            to = "any";
            trafficType = "icmp";
            action = "allow";
          }
          {
            id = "allow-client-to-wan";
            priority = 20;
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "external"; uplinks = [ "wan" ]; };
            trafficType = "icmp";
            action = "allow";
          }
        ];
      };

      topology.nodes = {
        access-admin = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "admin"; } ];
        };
        access-client = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
        };
        access-mgmt = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "mgmt"; } ];
        };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
      };

      topology.links = [
        [ "access-admin" "downstream" ]
        [ "access-client" "downstream" ]
        [ "access-mgmt" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
NIX

nix run "$ROOT#compile" -- "$input_file" >"$output_json"

jq -e '
  [
    .sites.esp0xdeadbeef."site-a".trafficPaths[]
    | select(.relationId == "allow-client-icmp-anywhere")
  ][0] as $path
  | $path.destination == "any"
    and $path.stagePath == [
      "access",
      "downstream-selector",
      "policy",
      "downstream-selector",
      "access"
    ]
    and $path.nodePathAlternatives == [
      [
        "access-client",
        "downstream",
        "policy",
        "downstream",
        "access-admin"
      ],
      [
        "access-client",
        "downstream",
        "policy",
        "downstream",
        "access-client"
      ],
      [
        "access-client",
        "downstream",
        "policy",
        "downstream",
        "access-mgmt"
      ]
    ]
' "$output_json" >/dev/null

expect_compile_failure() {
  local label="$1"
  local input="$2"
  local expected="$3"
  local output
  local rc

  set +e
  output="$(nix run "$ROOT#compile" -- "$input" 2>&1)"
  rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL ${label}: expected compiler failure" >&2
    exit 1
  fi

  if ! grep -qF "$expected" <<<"$output"; then
    echo "FAIL ${label}: missing diagnostic ${expected}" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
}

ineligible_input="${tmp_dir}/wildcard-ineligible-inventory-fanout.nix"
cat >"$ineligible_input" <<'NIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };

      ownership.prefixes = [
        { kind = "tenant"; name = "client"; ipv4 = "10.20.20.0/24"; }
        { kind = "tenant"; name = "admin"; ipv4 = "10.20.10.0/24"; }
      ];

      communicationContract = {
        trafficTypes = [
          { name = "icmp"; match = [ { proto = "icmp"; family = "any"; } ]; }
        ];
        services = [ ];
        relations = [
          {
            id = "allow-client-icmp-anywhere";
            priority = 10;
            from = { kind = "tenant"; name = "client"; };
            to = "any";
            trafficType = "icmp";
            action = "allow";
          }
          {
            id = "allow-client-to-wan";
            priority = 20;
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "external"; uplinks = [ "wan" ]; };
            trafficType = "icmp";
            action = "allow";
          }
        ];
      };

      topology.nodes = {
        access-admin = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "admin"; } ];
        };
        access-client = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
        };
        "br-uplink0:ens80" = {
          role = "access";
        };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
      };

      topology.links = [
        [ "access-admin" "downstream" ]
        [ "access-client" "downstream" ]
        [ "br-uplink0:ens80" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
NIX

expect_compile_failure \
  "wildcard-ineligible-inventory-fanout" \
  "$ineligible_input" \
  "E_TRAFFIC_PATH_WILDCARD_DESTINATION_INELIGIBLE"

empty_input="${tmp_dir}/wildcard-empty-graph.nix"
cat >"$empty_input" <<'NIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };

      communicationContract = {
        trafficTypes = [
          { name = "icmp"; match = [ { proto = "icmp"; family = "any"; } ]; }
        ];
        services = [ ];
        relations = [
          {
            id = "allow-wan-icmp-anywhere";
            priority = 10;
            from = { kind = "external"; uplinks = [ "wan" ]; };
            to = "any";
            trafficType = "icmp";
            action = "allow";
          }
        ];
      };

      topology.nodes = {
        "br-uplink0:ens80" = {
          role = "access";
        };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
      };

      topology.links = [
        [ "br-uplink0:ens80" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
NIX

expect_compile_failure \
  "wildcard-empty-graph" \
  "$empty_input" \
  "E_TRAFFIC_PATH_WILDCARD_DESTINATION_EMPTY"

echo "PASS wildcard-target-traffic-paths"
