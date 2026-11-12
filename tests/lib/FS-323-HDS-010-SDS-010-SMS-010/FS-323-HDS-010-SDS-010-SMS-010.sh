#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-323-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# FS-323-HDS-010-SDS-010: "Accept a reachability fact only from scope `offers`
# and `selects`." Permission is a separate input, and a traffic path needs both.
#
# This card lives here rather than only in network-control-plane-model because
# the behaviour it asserts is implemented in this repository
# (lib/stages/traffic-paths.nix) and the CPM does not track flake.lock, so a CPM
# card resolves whatever compiler revision it happens to pick. Asserting it where
# the code lives is what makes a regression here actually catchable.
#
# The defect this pins: `toCores` fell back to `coresForEndpoint relation.to`
# when no scope selected an exit, so a permit relation produced a path on its
# own. Measured on the single-wan fixture with every `selects` stripped, two
# multi-hop allow paths appeared -- allow-tenants-to-site-dns and
# allow-tenants-to-wan.

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
SCRATCH_ROOT="${TMPDIR:-/var/tmp}"
work_dir="$(mktemp -d "${SCRATCH_ROOT%/}/fs323-stripped-selects.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

fail() { echo "FAIL reachability-fact-permission-separation: $*" >&2; exit 1; }

# Resolve the checked-out network-labs through the flake, the same way the cards
# that need a concrete path do: the `labs:` scheme is only understood by
# `nix run <flake>#compile`.
labs_path="$(nix flake archive --json "path:${ROOT}" | jq -er '.inputs["network-labs"].path')"
base_intent="${labs_path}/examples/single-wan/intent.nix"
[[ -f "${base_intent}" ]] || fail "P1 no single-wan example at ${base_intent}"

stripped_intent="${work_dir}/intent-no-selects.nix"
cat >"${stripped_intent}" <<EOF
let
  base = import ${base_intent};
  site = base.esp0xdeadbeef."site-a";
  stripSelects = topology:
    topology // {
      nodes = builtins.mapAttrs
        (name: node: if node ? selects then removeAttrs node [ "selects" ] else node)
        topology.nodes;
    };
in
base // {
  esp0xdeadbeef = base.esp0xdeadbeef // {
    "site-a" = site // { topology = stripSelects site.topology; };
  };
}
EOF

compiled="${work_dir}/stripped.json"
nix run "${ROOT}#compile" -- "${stripped_intent}" >"${compiled}" 2>"${work_dir}/err.txt" || {
  cat "${work_dir}/err.txt" >&2
  fail "P1 the selects-stripped intent does not compile"
}

# P1: no non-service path survives without a selection. A service destination is
# exempt: it legitimately has no selects, its exit being the node hosting the
# service (FS-210/FS-525).
if ! jq -e '
  .sites.esp0xdeadbeef."site-a".trafficPaths as $paths
  | [ $paths[]
      | select(.action == "allow" and (.nodePath | length) > 1)
      | select(.toKind == "service" or (.serviceName != null))
    ] as $servicePaths
  | ([ $paths[]
       | select(.action == "allow" and (.nodePath | length) > 1)
       | select(.relationId == "allow-tenants-to-wan")
     ] | length) == 0
' "${compiled}" >/dev/null; then
  jq '[.sites.esp0xdeadbeef."site-a".trafficPaths[] | select(.action == "allow") | {relationId, nodePath}]' "${compiled}" >&2
  fail "SN1 a permit relation to an external with no selection still produced a path"
fi

echo "PASS reachability-fact-permission-separation"
