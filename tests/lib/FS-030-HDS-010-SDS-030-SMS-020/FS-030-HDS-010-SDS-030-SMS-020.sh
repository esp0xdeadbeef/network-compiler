#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-030-HDS-010-SDS-030-SMS-020
# GAMP-SCOPE: software-module-test
#
# A compiler-asserted traffic path must be derived, not declared.
#
# WHY THIS TEST EXISTS (regression, measured 2026-11-10)
# -----------------------------------------------------
# A cobalt tenant was granted `allow-cobalt-clients-to-wan`. The compiler
# emitted the canonical path:
#
#   nodePath = [ access-clients, downstream-selector, policy,
#                upstream-selector, core ]
#
# from a HARDCODED stage list (lib/stages/traffic-paths/stages.nix:
# `accessToCore = [ "access" "downstream-selector" "policy"
#                   "upstream-selector" "core" ]`), with each node filled by
# `firstRole <stage>` (lib/stages/traffic-paths.nix: `nodeForStage`). No part
# of that path was checked against the fabric that was actually emitted.
#
# The realized site had no route from `downstream-selector` toward the policy
# point, so the tenant received ICMP network-unreachable one hop in:
#
#   traceroute 1.1.1.1
#    1  10.2.30.1
#    2  10.1.0.1  !N
#
# Every downstream layer agreed with the compiler:
#   - network-forwarding-model `traffic-path-validation` checks only SN1
#     (relationId exists) and SN2 (action matches) -- never hop routability,
#     by its own documented scope;
#   - the CPM faithfully attached the routes it was given, per interface;
#   - the renderer faithfully emitted those routes;
#   - no HAT/SAT row had ever run, so no packet was ever sent.
#
# The URS forbids exactly this construction:
#   "The forwarding fabric between roles -- the next-hop links, selector roles,
#    and per-scope peer links -- is realization and shall be derived from
#    modeled reachability and permission facts, not declared as intent wiring."
#
# WHAT THIS TEST ASSERTS
# ----------------------
# The compiler has no routes, so it cannot prove a path is routable. It
# therefore must not present `nodePath` as a realized fact. Either:
#
#   (a) the field is marked as an intended/declared plan rather than an
#       observed path (so a consumer cannot mistake it for proof), or
#   (b) the compiler fails loudly when it cannot derive the path.
#
# This test accepts either resolution and fails while the compiler silently
# presents a synthesized path as if it were realized.

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

output_json="${tmp_dir}/compiled.json"
all_passed=true

echo "--- Compiling the multi-select fixture ---"
if ! nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/fs322-multi-select.nix" >"$output_json" 2>"${tmp_dir}/compile.err"; then
  echo "FAIL: fixture did not compile"
  cat "${tmp_dir}/compile.err" >&2
  exit 1
fi

path_count=$(jq -r '[.sites[][].trafficPaths[]?] | length' "$output_json")
if [[ "${path_count}" -eq 0 ]]; then
  echo "FAIL: fixture produced no traffic paths; the test would pass vacuously"
  exit 1
fi
echo "  traffic paths: ${path_count}"

echo ""
echo "--- P1: no traffic path may present a synthesized nodePath as realized ---"
#
# A path is suspect when it carries a multi-hop `nodePath` while the artifact
# provides no route evidence that would make that path traversable. The
# compiler emits no routes anywhere, so "has nodePath but no realization
# marker" is precisely the unsafe shape.
synthesized=$(jq -r '
  [ .sites[][].trafficPaths[]?
    | select((.nodePath // []) | length > 1)
    | select((.pathRealization // "realized") == "realized")
  ] | length
' "$output_json")

if [[ "${synthesized}" -eq 0 ]]; then
  echo "PASS P1: no multi-hop path claims to be realized without route evidence"
else
  echo "FAIL P1: ${synthesized} multi-hop traffic path(s) present a synthesized nodePath without a realization marker."
  echo "         The compiler derives nodePath from a hardcoded stage list and emits no routes,"
  echo "         so it cannot prove the hops are traversable. Mark these paths as an intended plan"
  echo "         (e.g. pathRealization = \"declared\") or derive them from resolved routing."
  jq -r '
    [ .sites[][].trafficPaths[]?
      | select((.nodePath // []) | length > 1)
      | select((.pathRealization // "realized") == "realized")
      | { relationId, nodePath }
    ] | .[0:3][]
  ' "$output_json"
  all_passed=false
fi

echo ""
echo "--- P2: a WAN path's stage list must match its node path length ---"
#
# A plan that names five stages but emits four nodes (or the reverse) is
# internally inconsistent regardless of routability.
bad_shape=$(jq -r '
  [ .sites[][].trafficPaths[]?
    | select((.stagePath // [] | length) != (.nodePath // [] | length))
    | .relationId
  ] | length
' "$output_json")

if [[ "${bad_shape}" -eq 0 ]]; then
  echo "PASS P2: every path has one node per stage"
else
  echo "FAIL P2: ${bad_shape} path(s) have a stagePath and nodePath of different length"
  all_passed=false
fi

echo ""
echo "--- P3: the same path shape must not be emitted for a fabric that cannot forward ---"
#
# The check above is a structural proxy. This one states the requirement
# directly: if a path crosses the selector/policy fabric, the artifact must
# either carry route evidence for each hop or be marked as an unverified plan.
crosses_fabric=$(jq -r '
  [ .sites[][].trafficPaths[]?
    | select((.nodePath // []) | index("downstream-selector") != null)
    | select((.pathRealization // "realized") == "realized")
  ] | length
' "$output_json")

if [[ "${crosses_fabric}" -eq 0 ]]; then
  echo "PASS P3: no unverified path claims to traverse the selector fabric"
else
  echo "FAIL P3: ${crosses_fabric} path(s) claim to cross downstream-selector with no route evidence."
  echo "         This is the exact shape that produced the cobalt egress outage:"
  echo "         the tenant reached the selector and was answered !N one hop later."
  all_passed=false
fi

echo ""
if [[ "${all_passed}" == true ]]; then
  echo "PASS FS-030-HDS-010-SDS-030-SMS-020: compiler paths do not overclaim realization"
else
  echo "FAIL FS-030-HDS-010-SDS-030-SMS-020: the compiler presents synthesized paths as realized" >&2
  exit 1
fi
