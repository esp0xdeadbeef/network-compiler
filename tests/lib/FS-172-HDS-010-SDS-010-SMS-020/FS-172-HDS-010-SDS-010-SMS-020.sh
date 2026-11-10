#!/usr/bin/env bash
# GAMP-ID: FS-172-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-172-HDS-010-SDS-010-SMS-020.md
# OWNER:  network-compiler
# MODULE: Declared-Versus-Derived Classifier  (reg.classify)
#
# Behavioural case against the real module. Not executed before commit.
#
# Predicates taken from the SMS:
#   P1  Every accepted source field is classified exactly once: `declared` or
#       `derivable`.
#   P4  The classifier creates no authority; it only says where a value comes
#       from.
#
# Seeded negatives the SMS requires:
#   SN1  A derivable field is identified as derivable, so supplying it can be
#        refused by the input boundary (see SMS-030).
#   SN2  A field no rule produces is classified `declared`, not defaulted.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL declared-versus-derived-classifier: $*" >&2; exit 1; }

reg_expr() {
  nix eval --no-write-lock-file --impure --json --expr '
    let
      f = builtins.getFlake "'"path:${repo_root}"'";
      pkgs = import f.inputs.nixpkgs { };
      reg = import "'"${repo_root}"'/lib/derivation-registry/default.nix" { lib = pkgs.lib; };
    in
      '"$1"''
}

# SN1: a fact a rule produces is derivable.
out="$(reg_expr 'reg.classify { field = "fabricSelectorRoles"; }' 2>&1)" || {
  fail "P1 classify(fabricSelectorRoles) failed
${out}"; }
[[ "${out}" == '"derivable"' ]] || fail "SN1 a rule-produced field classified as ${out}, expected \"derivable\""

# SN2: a field no rule produces is declared input, not defaulted.
out="$(reg_expr 'reg.classify { field = "notProducedByAnyRule"; }' 2>&1)" || {
  fail "P1 classify(notProducedByAnyRule) failed
${out}"; }
[[ "${out}" == '"declared"' ]] || fail "SN2 an unruled field classified as ${out}, expected \"declared\""

# P1: every entry's derived fact classifies as derivable, so the two surfaces
# cannot disagree about which fields rules own.
out="$(reg_expr '
  let
    facts = map (e: e.derivedFact) reg.defaultEntries;
    bad = builtins.filter (d: reg.classify { field = d; } != "derivable") facts;
  in
    bad
' 2>&1)" || {
  fail "P1 the entry/classifier cross-check could not be evaluated
${out}"; }
[[ "${out}" == "[]" ]] || fail "P1 these derived facts do not classify as derivable: ${out}"

echo "PASS declared-versus-derived-classifier"
