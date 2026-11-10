#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-482-HDS-010-SDS-010-SMS-040
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
system="${NIX_SYSTEM:-$(nix eval --no-write-lock-file --impure --raw --expr 'builtins.currentSystem')}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "missing required command: $1" >&2
    exit 1
  }
}

require_cmd jq

flake_input_path() {
  local input_name="$1"
  if [[ "${input_name}" == "network-labs" && -n "${NETWORK_LABS_PATH:-}" ]]; then
    realpath "${NETWORK_LABS_PATH}"
    return
  fi
  nix flake archive --json "path:${ROOT}" \
    | jq -er ".inputs[\"${input_name}\"].path"
}

labs="$(flake_input_path network-labs)"
intent_path="${labs}/examples/single-wan-bgp/intent.nix"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

compile_paths() {
  local intent="$1"
  nix eval --no-write-lock-file --impure --json --expr '
    let
      flake = builtins.getFlake "'"path:${ROOT}"'";
    in
      flake.libBySystem."'"${system}"'".compilePath "'"${intent}"'"
  '
}

# FS-482: BGP route availability grants no payload permission. Selecting BGP is a
# routing decision; the permission set must be exactly what the relations say,
# unchanged by whether BGP is selected.
#
# The A/B fixture toggles `behaviors = ["bgp"]` on the same model, so any
# difference in the permission set is attributable to BGP alone.

bgp_on_intent="${tmp_dir}/intent-bgp-on.nix"
cat >"${bgp_on_intent}" <<EOF
import ${intent_path}
EOF

bgp_off_intent="${tmp_dir}/intent-bgp-off.nix"
cat >"${bgp_off_intent}" <<EOF
let
  base = import ${intent_path};
  strip = nodes: builtins.mapAttrs
    (n: node:
      if node ? behaviors
      then node // { behaviors = builtins.filter (b: b != "bgp") node.behaviors; }
      else node)
    nodes;
  sites = builtins.mapAttrs
    (s: site:
      site // { topology = site.topology // { nodes = strip site.topology.nodes; }; })
    base.esp0xdeadbeef;
in
base // { esp0xdeadbeef = sites; }
EOF

compile_paths "${bgp_on_intent}"  >"${tmp_dir}/on.json"
compile_paths "${bgp_off_intent}" >"${tmp_dir}/off.json"

permission_projection='
  [ .sites.esp0xdeadbeef."site-a".relations[]
    | { action, from, to, trafficType } ]
  | sort_by(tostring)
'

if ! ON_JSON="${tmp_dir}/on.json" nix eval --no-write-lock-file --impure --json --expr '
  let
    data = builtins.fromJSON (builtins.readFile (builtins.getEnv "ON_JSON"));
    site = data.sites.esp0xdeadbeef."site-a";
  in
    builtins.length site.relations > 0
' | grep -qx true; then
  echo "FAIL no-payload-grant: the BGP model carries no relations, so the case has nothing to compare" >&2
  exit 1
fi

jq -S -c "${permission_projection}" "${tmp_dir}/on.json"  >"${tmp_dir}/on.perm"
jq -S -c "${permission_projection}" "${tmp_dir}/off.json" >"${tmp_dir}/off.perm"

if ! diff -q "${tmp_dir}/on.perm" "${tmp_dir}/off.perm" >/dev/null; then
  echo "FAIL no-payload-grant: selecting BGP changed the payload permission set, so route availability granted or widened a permission" >&2
  diff "${tmp_dir}/off.perm" "${tmp_dir}/on.perm" >&2 || true
  exit 1
fi

# SN1: no permission record may carry routing provenance. A relation whose source
# names a route, a peer, or a BGP advertisement is a route-derived grant.
if ! ON_JSON="${tmp_dir}/on.json" nix eval --no-write-lock-file --impure --expr '
  let
    data = builtins.fromJSON (builtins.readFile (builtins.getEnv "ON_JSON"));
    site = data.sites.esp0xdeadbeef."site-a";
    forbiddenText = [ "bgp-route" "learned-route" "advertisement" "peer-adjacency" ];
    mentions = r:
      let s = builtins.toJSON r;
      in builtins.any (needle: builtins.match ".*${needle}.*" s != null) forbiddenText;
  in
    !(builtins.any mentions site.relations)
' | grep -qx true; then
  echo "FAIL no-payload-grant: a permission record names routing provenance instead of a relation" >&2
  exit 1
fi

# SN2: deny-by-default is unchanged by selecting BGP. A tenant with no relation
# must have no allow path, and the BGP model must not add one.
if ! ON_JSON="${tmp_dir}/on.json" nix eval --no-write-lock-file --impure --expr '
  let
    data = builtins.fromJSON (builtins.readFile (builtins.getEnv "ON_JSON"));
    site = data.sites.esp0xdeadbeef."site-a";
    relationCount = builtins.length site.relations;
    allowPaths = builtins.filter (p: p.action == "allow") site.trafficPaths;
    pathIds = map (p: p.relationId) allowPaths;
  in
    builtins.length allowPaths <= relationCount
' | grep -qx true; then
  echo "FAIL no-payload-grant: the BGP model produced more allow paths than modeled relations, so deny-by-default was relaxed" >&2
  exit 1
fi

echo "PASS no-payload-grant"
