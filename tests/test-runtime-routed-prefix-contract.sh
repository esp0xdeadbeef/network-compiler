#!/usr/bin/env bash
set -euo pipefail

root="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
input_file="$(mktemp)"
out="$(mktemp)"
trap 'rm -f "${input_file}" "${out}"' EXIT

cat >"${input_file}" <<'EOF'
{
  espbranch.site-b = {
    ownership.prefixes = [
      {
        kind = "tenant";
        name = "hostile";
        ipv4 = "10.70.10.0/24";
        ipv6 = "fd42:dead:feed:70::/64";
        routedPrefixes = [
          {
            allocation = "runtime";
            family = "ipv6";
            name = "site-b-hostile-public";
            delegatedPrefixLength = 64;
            perTenantPrefixLength = 64;
            slot = 0;
            sourceFile = "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile";
          }
        ];
      }
    ];
    communicationContract = {
      trafficTypes = [ ];
      services = [ ];
      relations = [
        {
          id = "allow-hostile-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "hostile"; };
          to = { kind = "external"; name = "wan"; };
          trafficType = "any";
          action = "allow";
        }
      ];
    };
    topology = {
      nodes = {
        core = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; };
        upstream.role = "upstream-selector";
        policy.role = "policy";
        downstream.role = "downstream-selector";
        access = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "hostile"; } ];
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
EOF

nix run "${root}#compile" -- \
  "${input_file}" \
  >"${out}"

jq -e '
  ..
  | objects
  | select(.routedPrefixes? != null and .name == "hostile")
  | .routedPrefixes[]
  | select(
      .allocation == "runtime"
      and .family == "ipv6"
      and .name == "site-b-hostile-public"
      and .delegatedPrefixLength == 64
      and .perTenantPrefixLength == 64
      and .slot == 0
      and .sourceFile == "/run/secrets/access-node-ipv6-prefix-espbranch-site-b-b-router-access-hostile")
' "${out}" >/dev/null || {
  echo "FAIL runtime-routed-prefix-contract: compiler must preserve intent-owned runtime routed-prefix metadata" >&2
  exit 1
}

echo "PASS runtime-routed-prefix-contract"
