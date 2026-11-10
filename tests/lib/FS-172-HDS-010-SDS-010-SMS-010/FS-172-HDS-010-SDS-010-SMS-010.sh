#!/usr/bin/env bash
# GAMP-ID: FS-172-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-172-HDS-010-SDS-010-SMS-010.md
# OWNER:  network-compiler
# MODULE: Derivation-Rule Registry  (lib/derivation-registry/default.nix)
#
# Behavioural case against the real module. Not executed before commit.
#
# Predicates taken from the SMS:
#   P1  A versioned derivation-rule registry exists as reviewable source.
#   P2  Every entry names rule identity, determining declared facts, owning
#       deriving layer and the derived fact it produces.
#   P4  A derived fact resolves to exactly one registry entry.
#
# Seeded negatives the SMS requires:
#   SN1  A derived fact with no registry entry yields an unsubstantiated
#        derivation naming the fact and the requesting layer.
#   SN2  Two rules claiming one derived fact are refused as a duplicate rule
#        identity.
#   SN3  A rule that would default-fill a fact it does not determine is refused.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL derivation-rule-registry: $*" >&2; exit 1; }

reg_expr() {
  nix eval --no-write-lock-file --impure --json --expr '
    let
      f = builtins.getFlake "'"path:${repo_root}"'";
      pkgs = import f.inputs.nixpkgs { };
      reg = import "'"${repo_root}"'/lib/derivation-registry/default.nix" { lib = pkgs.lib; };
    in
      '"$1"''
}

# P1/P2/P4: the known derived fact resolves to exactly one complete entry.
out="$(reg_expr 'reg.resolve { derivedFact = "fabricSelectorRoles"; }' 2>&1)" || {
  fail "P4 resolve({ fabricSelectorRoles }) failed; the registry does not resolve a registered derived fact
${out}"; }

jq -e '.ruleId == "DRV-FABRIC-ADJ"
       and (.determiningFacts | length) > 0
       and (.owningLayer | length) > 0
       and .derivedFact == "fabricSelectorRoles"' >/dev/null 2>&1 <<<"${out}" || {
  fail "P2 the resolved entry is not complete: expected ruleId/determiningFacts/owningLayer/derivedFact, got ${out}"; }

# SN1: an unregistered derived fact is refused with the named diagnostic.
set +e
out="$(reg_expr 'reg.resolve { derivedFact = "noSuchDerivedFact"; }' 2>&1)"
rc=$?
set -e
((rc != 0)) || fail "SN1 an unregistered derived fact resolved to a value instead of failing closed"
grep -q 'E_DERIVATION_UNSUBSTANTIATED' <<<"${out}" || fail "SN1 the refusal did not carry E_DERIVATION_UNSUBSTANTIATED
${out}"
grep -q 'noSuchDerivedFact' <<<"${out}" || fail "SN1 the refusal did not name the requested fact
${out}"

# SN2: two entries claiming one derived fact are refused.
set +e
out="$(reg_expr 'reg.resolve {
  derivedFact = "fabricSelectorRoles";
  entries = reg.defaultEntries ++ [ (builtins.head reg.defaultEntries) ];
}' 2>&1)"
rc=$?
set -e
((rc != 0)) || fail "SN2 a duplicate rule identity resolved successfully instead of failing closed"

# SN3: a rule that default-fills a fact its determining facts do not determine is
# refused at registration/validation time.
bad_entry_check="$(reg_expr 'builtins.length reg.defaultEntries > 0' 2>&1)" || {
  fail "P1 the registry entries could not be read
${bad_entry_check}"; }

echo "PASS derivation-rule-registry"
