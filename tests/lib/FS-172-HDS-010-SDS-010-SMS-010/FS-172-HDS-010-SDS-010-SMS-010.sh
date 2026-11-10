#!/usr/bin/env bash
# GAMP-ID: FS-172-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-172-HDS-010-SDS-010-SMS-010.md
# OWNER:  network-compiler
# MODULE: Derivation-Rule Registry
#
# THIS TEST IS EXPECTED TO FAIL. The specification exists; the module does not.
# Do not weaken the test to make it pass — implement the module.
#
# Predicates taken from the SMS:
#   P1  A versioned derivation-rule registry exists as reviewable source.
#   P2  Every entry names rule identity, determining declared facts, owning
#       deriving layer, and the derived fact it produces.
#   P3  The registry is the single authority: the Derivation-Rule Registry Map in
#       FS-172-HDS-010-SDS-010 is not restated or renamed here.
#   P4  A derived fact resolves to exactly one registry entry.
#   P5  A rule that would default-fill a fact it does not determine is refused.
#
# Seeded negatives the SMS requires:
#   SN1  A derived fact with no registry entry yields an
#        unsubstantiated-derivation diagnostic naming the fact and layer.
#   SN2  A second rule claiming a fact already produced is refused as a
#        duplicate rule identity.
#   SN3  A rule used to default-fill an undetermined fact is refused.
#
# To implement: add the registry as versioned source, expose a resolver that maps
# a derived fact to exactly one entry, and make the three seeded negatives above
# fail closed with those diagnostics.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL derivation-rule-registry: $*" >&2; exit 1; }

# P1: the registry must exist as source in this repository.
# Registry *source*: a directory can never carry rule identities, so select the
# Nix files only. A registry split across a directory (data + refusal logic) is
# therefore found through its `.nix` members, not through the directory itself.
mapfile -t registries < <(find "${repo_root}/lib" "${repo_root}/src" -maxdepth 4 -type f -name '*.nix' \
  \( -name 'derivation-registry*' -o -name '*derivation*rules*' -o -path '*/derivation-registry/*' \) 2>/dev/null | LC_ALL=C sort)

if ((${#registries[@]} == 0)); then
  fail "P1 no derivation-rule registry source exists (expected lib/derivation-registry.nix or equivalent under ${repo_root})"
fi

registry="${registries[0]}"

# P2: entries must carry the four fields the SMS names.
if ! grep -qE 'rule(Id|Identity)|rule_identity|DRV-' "${registry}"; then
  fail "P2 ${registry} carries no rule identity (expected ruleId/ruleIdentity or a DRV-* identifier)"
fi
if ! grep -qiE 'determining|facts|inputs' "${registry}"; then
  fail "P2 ${registry} names no determining declared facts for its rules"
fi
if ! grep -qiE 'owningLayer|layer|owner' "${registry}"; then
  fail "P2 ${registry} names no owning deriving layer for its rules"
fi
if ! grep -qiE 'derivedFact|produces|derived' "${registry}"; then
  fail "P2 ${registry} names no derived fact for its rules"
fi

# P3: the registry must not restate the SDS map. If it copies the table it is a
# second authority, which the SMS forbids.
if grep -qE 'DRV-FABRIC-ADJ.*DRV-DNS-RESOLVER-PATH.*DRV-PREFIX-EXIT-BINDING' "${registry}"; then
  fail "P3 ${registry} restates the SDS registry map inline instead of referencing it"
fi

# SN1: an unresolvable derived fact must produce the diagnostic, not a default.
if ! grep -rqiE 'unsubstantiated' "${repo_root}/lib" "${repo_root}/src" 2>/dev/null; then
  fail "SN1 no unsubstantiated-derivation diagnostic exists for a derived fact with no registry entry"
fi

# SN2: duplicate rule identity must be refused.
if ! grep -rqiE 'duplicate.*(rule|identity)|rule-identity-duplicate' "${repo_root}/lib" "${repo_root}/src" 2>/dev/null; then
  fail "SN2 no duplicate-rule-identity rejection exists"
fi

# SN3: a rule that default-fills an undetermined fact must be refused.
if ! grep -rqiE 'default.?fill' "${repo_root}/lib" "${repo_root}/src" 2>/dev/null; then
  fail "SN3 no default-fill rejection exists for a rule that does not determine its output"
fi

echo "PASS derivation-rule-registry"
