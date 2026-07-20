#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-260-HDS-010-SDS-010-SMS-010
# GAMP-ID: SMT-COMP-FS260-DEFAULT-SITE-FABRIC-CHAIN-001
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

input_file="${tmp_dir}/default-chain.nix"
output_json="${tmp_dir}/default-chain.json"

cat >"${input_file}" <<'NIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };

      ownership.prefixes = [
        { kind = "tenant"; name = "client"; ipv4 = "10.20.20.0/24"; }
      ];

      communicationContract.relations = [
        {
          id = "allow-client-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
      ];

      topology.nodes = {
        access-client = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
        };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core-wan = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
      };

      topology.links = [
        [ "access-client" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core-wan" ]
      ];
    };
  };
}
NIX

nix run "${ROOT}#compile" -- "${input_file}" >"${output_json}"

jq -e '
  .sites.esp0xdeadbeef."site-a".trafficPaths
  | map(select(.relationId == "allow-client-to-wan"))
  | length == 1
    and .[0].stagePath == [
      "access",
      "downstream-selector",
      "policy",
      "upstream-selector",
      "core"
    ]
    and .[0].nodePath == [
      "access-client",
      "downstream",
      "policy",
      "upstream",
      "core-wan"
    ]
    and .[0].nodePathAlternatives == [[
      "access-client",
      "downstream",
      "policy",
      "upstream",
      "core-wan"
    ]]
    and .[0].requiresPolicy == true
    and .[0].forbidsCoreToCoreP2P == true
    and .[0].p2pIsolationKey == "allow-client-to-wan"
' "${output_json}" >/dev/null

expect_compile_failure() {
  local name="$1"
  local input="$2"
  local expected="$3"
  local output
  local rc

  set +e
  output="$(nix run "${ROOT}#compile" -- "${input}" 2>&1)"
  rc=$?
  set -e

  if [[ "${rc}" -eq 0 ]]; then
    echo "FAIL ${name}: expected compiler failure" >&2
    exit 1
  fi

  if ! grep -q "${expected}" <<<"${output}"; then
    echo "FAIL ${name}: missing ${expected}" >&2
    printf '%s\n' "${output}" >&2
    exit 1
  fi
}

missing_role_input="${tmp_dir}/missing-upstream-role.nix"
cat >"${missing_role_input}" <<'NIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };

      ownership.prefixes = [
        { kind = "tenant"; name = "client"; ipv4 = "10.20.20.0/24"; }
      ];

      communicationContract.relations = [
        {
          id = "allow-client-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
      ];

      topology.nodes = {
        access-client = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
        };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream = { };
        core-wan = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
      };

      topology.links = [
        [ "access-client" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core-wan" ]
      ];
    };
  };
}
NIX

expect_compile_failure \
  "missing-required-upstream-role" \
  "${missing_role_input}" \
  "E_TOPO_MISSING_UPSTREAM_SELECTOR"

noncanonical_input="${tmp_dir}/noncanonical-link.nix"
cat >"${noncanonical_input}" <<'NIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };

      ownership.prefixes = [
        { kind = "tenant"; name = "client"; ipv4 = "10.20.20.0/24"; }
      ];

      communicationContract.relations = [
        {
          id = "allow-client-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
      ];

      topology.nodes = {
        access-client = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
        };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core-wan = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
      };

      topology.links = [
        [ "access-client" "downstream" ]
        [ "downstream" "core-wan" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core-wan" ]
      ];
    };
  };
}
NIX

expect_compile_failure \
  "noncanonical-stage-link" \
  "${noncanonical_input}" \
  "E_TOPO_NON_CANONICAL_STAGE_LINK"

alternate_structure_input="${tmp_dir}/unmodeled-alternate-structure.nix"
cat >"${alternate_structure_input}" <<'NIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };

      ownership.prefixes = [
        { kind = "tenant"; name = "client"; ipv4 = "10.20.20.0/24"; }
      ];

      communicationContract.relations = [
        {
          id = "allow-client-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
      ];

      topology = {
        structure = "direct-core-shortcut";
        nodes = {
          access-client = {
            role = "access";
            attachments = [ { kind = "tenant"; name = "client"; } ];
          };
          downstream.role = "downstream-selector";
          policy.role = "policy";
          upstream.role = "upstream-selector";
          core-wan = {
            role = "core";
            uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
          };
        };
        links = [
          [ "access-client" "downstream" ]
          [ "downstream" "policy" ]
          [ "policy" "upstream" ]
          [ "upstream" "core-wan" ]
        ];
      };
    };
  };
}
NIX

expect_compile_failure \
  "unmodeled-alternate-structure" \
  "${alternate_structure_input}" \
  "E_TOPO_UNMODELED_ALTERNATE_STRUCTURE"

echo "PASS fs260-default-site-fabric-chain"
