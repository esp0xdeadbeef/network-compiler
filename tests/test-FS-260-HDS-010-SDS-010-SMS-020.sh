#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-260-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

archive_json="${tmp_dir}/archive.json"

nix flake archive --json "path:${ROOT}" >"${archive_json}"
labs_path="${ROOT}/tests/fixtures"

compile_example() {
  local example="$1"
  local output_json="$2"
  nix run "$ROOT#compile" -- "${labs_path}/examples/${example}/intent.nix" >"${output_json}"
}

compile_example "s-router-overlay-dns-lane-policy" "${tmp_dir}/dns-lane.json"
compile_example "tri-site-s-router-overlay-egress" "${tmp_dir}/tri-site.json"
compile_example "tri-site-dual-wan-overlay-integration-static" "${tmp_dir}/dual-wan.json"

expect_compile_failure() {
  local name="$1"
  local input_file="$2"
  local expected="$3"
  local output
  local rc

  set +e
  output="$(nix run "$ROOT#compile" -- "${input_file}" 2>&1)"
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

jq -e '
  .sites.esp0xdeadbeef["site-a"].trafficPaths
  | map(select(.relationId == "allow-tenants-to-uplinks"))
  | .[0]
  | .stagePath == [
      "access",
      "downstream-selector",
      "policy",
      "upstream-selector",
      "core"
    ]
    and .corePathNodes == [
      "s-router-core-isp-a",
      "s-router-core-isp-b"
    ]
    and .forbidsCoreToCoreP2P == true
    and .p2pIsolationKey == "allow-tenants-to-uplinks"
' "${tmp_dir}/dns-lane.json" >/dev/null

jq -e '
  .sites.esp0xdeadbeef["site-a"].trafficPaths
  | map(select(.relationId == "allow-east-west-to-sitea-mgmt-dns"))
  | .[0]
  | .stagePath == [
      "core",
      "access",
      "downstream-selector",
      "policy",
      "downstream-selector",
      "access"
    ]
    and .nodePath == [
      "s-router-core-nebula",
      "s-router-access-client",
      "s-router-downstream-selector",
      "s-router-policy-only",
      "s-router-downstream-selector",
      "s-router-access-mgmt"
    ]
' "${tmp_dir}/dns-lane.json" >/dev/null

jq -e '
  .sites.esp.edge.trafficPaths
  | map(select(.relationId == "allow-hostile-overlay-egress-to-wan"))
  | .[0]
  | .stagePath == [
      "core",
      "upstream-selector",
      "policy",
      "upstream-selector",
      "core"
    ]
    and .nodePath == [
      "edge-example-router-nebula-core",
      "edge-example-router-upstream",
      "edge-example-router-policy",
      "edge-example-router-upstream",
      "edge-example-router-core"
    ]
    and .forbidsCoreToCoreP2P == true
    and .p2pIsolationKey == "allow-hostile-overlay-egress-to-wan"
' "${tmp_dir}/tri-site.json" >/dev/null

jq -e '
  .sites.esp0xdeadbeef["site-a"].trafficPaths
  | map(select(.relationId == "allow-sitec-storage-underlay-to-uplinks"))
  | .[0]
  | .stagePath == [
      "core",
      "access",
      "downstream-selector",
      "policy",
      "upstream-selector",
      "core"
    ]
    and .nodePath == [
      "s-router-core-nebula",
      "s-router-access-mgmt",
      "s-router-downstream-selector",
      "s-router-policy-only",
      "s-router-upstream-selector",
      "s-router-core-isp-a"
    ]
    and .corePathNodes == [
      "s-router-core-nebula",
      "s-router-core-isp-a",
      "s-router-core-isp-b"
    ]
' "${tmp_dir}/dual-wan.json" >/dev/null

expect_compile_failure \
  "direct-core-to-core-link" \
  "${ROOT}/tests/negative/core-to-core-link.nix" \
  "E_TOPO_NON_CANONICAL_STAGE_LINK"

missing_role_chain_input="${tmp_dir}/missing-role-chain.nix"
cat >"${missing_role_chain_input}" <<'NIX'
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
  "missing-explicit-upstream-role-chain" \
  "${missing_role_chain_input}" \
  "E_TOPO_MISSING_UPSTREAM_SELECTOR"

echo "PASS FS-260-HDS-010-SDS-010-SMS-020"