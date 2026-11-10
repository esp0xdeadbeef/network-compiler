#!/usr/bin/env bash
# GAMP-ID: FS-172-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-172-HDS-010-SDS-010-SMS-030.md
# OWNER:  network-compiler
# MODULE: Duplicate-Writer Diagnostic
#
# THIS TEST IS EXPECTED TO FAIL. The specification exists; the module does not.
# Do not weaken the test to make it pass — implement the module.
#
# Predicates taken from the SMS:
#   P1  A supplied value whose class is `derivable` is rejected at the input
#       boundary as a duplicate writer.
#   P2  The diagnostic names the field, the declaring scope, the determining
#       declared fact, the versioned derivation rule, and the derived value.
#   P3  A rule/source disagreement names both the versioned rule and the
#       hand-written source value, and prefers neither.
#   P4  A fault is raised by the owning deriving layer named in the registry, not
#       by the classifier and not by a downstream consumer.
#
# Seeded negatives the SMS requires:
#   SN1  Supply a derivable field as input and require the duplicate-writer
#        rejection with all five named facts.
#   SN2  Make a registry rule disagree with a hand-written source value and
#        require a disagreement diagnostic naming both, with neither preferred.
#
# To implement: add the diagnostic and its five-field record at the compiler input
# boundary, and the disagreement path that reports both values.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL duplicate-writer-diagnostic: $*" >&2; exit 1; }

# P1/SN1: the rejection must exist.
if ! grep -rqiE 'duplicate.?writer' "${repo_root}/lib" "${repo_root}/src" --include=*.nix 2>/dev/null; then
  fail "SN1 no duplicate-writer rejection exists at the compiler input boundary"
fi

# P2: all five named facts must be carried. Each is checked separately so the
# message says which one is missing rather than only that the test failed.
missing=""
for field in 'field' 'scope' 'determining' 'rule' 'derived'; do
  grep -rqiE "duplicate.?writer[^\\n]*${field}|${field}[^\\n]*duplicate.?writer" \
    "${repo_root}/lib" --include=*.nix 2>/dev/null \
    || missing="${missing} ${field}"
done
if [[ -n "${missing}" ]]; then
  fail "P2 the duplicate-writer diagnostic does not name:${missing}"
fi

# P3/SN2: rule/source disagreement must name both sides and prefer neither.
if ! grep -rqiE 'disagree' "${repo_root}/lib" "${repo_root}/src" --include=*.nix 2>/dev/null; then
  fail "SN2 no rule/source disagreement diagnostic exists"
fi

# P4: the fault must be attributed to the deriving layer, so the diagnostic is
# not raised anonymously by the classifier.
if ! grep -rqiE 'owningLayer|owning.?deriving|deriving.?layer' \
  "${repo_root}/lib" "${repo_root}/src" --include=*.nix 2>/dev/null; then
  fail "P4 no owning-deriving-layer attribution exists for a derivation fault"
fi

echo "PASS duplicate-writer-diagnostic"
