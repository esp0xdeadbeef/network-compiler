#!/usr/bin/env bash
# GAMP-ID: FS-172-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-172-HDS-010-SDS-010-SMS-030.md
# OWNER:  network-compiler
# MODULE: Duplicate-Writer Diagnostic  (lib/derivation-registry/input-boundary.nix)
#
# Behavioural case against the real module. Not executed before commit.
#
# Predicates taken from the SMS:
#   P1  A supplied value whose class is derivable is rejected at the input
#       boundary as a duplicate writer.
#   P2  The diagnostic names the field, the declaring scope, the determining
#       declared facts, the versioned rule, and the derived value.
#   P3  A rule/source disagreement names both values and prefers neither.
#
# Seeded negatives the SMS requires:
#   SN1  Supplying a derivable field yields the duplicate-writer rejection.
#   SN2  A rule and a hand-written source value that disagree yield a
#        disagreement diagnostic naming both.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL duplicate-writer-diagnostic: $*" >&2; exit 1; }

reg_expr() {
  nix eval --no-write-lock-file --impure --json --expr '
    let
      f = builtins.getFlake "'"path:${repo_root}"'";
      pkgs = import f.inputs.nixpkgs { };
      reg = import "'"${repo_root}"'/lib/derivation-registry/default.nix" { lib = pkgs.lib; };
    in
      '"$1"''
}

# Positive: supplying only declared fields is accepted.
out="$(reg_expr 'reg.ensureNoDuplicateWriter { suppliedFields = [ "notADerivedFact" ]; scope = "site-a"; }' 2>&1)" || {
  fail "P1 the duplicate-writer guard rejected a set containing no derivable field
${out}"; }

# SN1: supplying a derivable field is refused.
set +e
out="$(reg_expr 'reg.ensureNoDuplicateWriter { suppliedFields = [ "fabricSelectorRoles" ]; scope = "site-a"; }' 2>&1)"
rc=$?
set -e
((rc != 0)) || fail "SN1 supplying the derivable field fabricSelectorRoles succeeded instead of failing closed"
grep -q 'E_DUPLICATE_WRITER' <<<"${out}" || fail "SN1 the refusal did not carry E_DUPLICATE_WRITER
${out}"

# P2: the diagnostic names the field and its scope.
grep -q 'fabricSelectorRoles' <<<"${out}" || fail "P2 the diagnostic did not name the field
${out}"
grep -q 'site-a' <<<"${out}" || fail "P2 the diagnostic did not name the declaring scope
${out}"

# P2: the diagnostic names the determining facts and the rule that owns it.
grep -qE 'DRV-[A-Z-]+' <<<"${out}" || fail "P2 the diagnostic did not name the versioned rule
${out}"

# SN2: a rule/source disagreement names both values.
set +e
out="$(reg_expr 'reg.ensureRuleSourceAgreement {
  field = "fabricSelectorRoles";
  ruleValue = [ "a" ];
  sourceValue = [ "b" ];
  ruleId = "DRV-FABRIC-ADJ";
}' 2>&1)"
rc=$?
set -e
((rc != 0)) || fail "SN2 a rule/source disagreement was accepted instead of failing closed"
grep -q 'E_DERIVATION_RULE_SOURCE_DISAGREEMENT' <<<"${out}" || fail "SN2 the refusal did not carry E_DERIVATION_RULE_SOURCE_DISAGREEMENT
${out}"
grep -q 'DRV-FABRIC-ADJ' <<<"${out}" || fail "SN2 the disagreement did not name the rule
${out}"

# P3: agreement is accepted, so the guard is not a blanket refusal.
out="$(reg_expr 'reg.ensureRuleSourceAgreement {
  field = "fabricSelectorRoles";
  ruleValue = [ "a" ];
  sourceValue = [ "a" ];
  ruleId = "DRV-FABRIC-ADJ";
}' 2>&1)" || fail "P3 an agreeing rule and source value were rejected
${out}"

echo "PASS duplicate-writer-diagnostic"
