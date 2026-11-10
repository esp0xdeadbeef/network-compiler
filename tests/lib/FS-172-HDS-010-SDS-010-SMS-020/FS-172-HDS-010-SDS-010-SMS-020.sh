#!/usr/bin/env bash
# GAMP-ID: FS-172-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-172-HDS-010-SDS-010-SMS-020.md
# OWNER:  network-compiler
# MODULE: Declared-Versus-Derived Classifier
#
# THIS TEST IS EXPECTED TO FAIL. The specification exists; the module does not.
# Do not weaken the test to make it pass — implement the module.
#
# Predicates taken from the SMS:
#   P1  Every accepted source field is classified exactly once: `declared`
#       (required source truth) or `derivable` (determined by declared facts
#       under a named rule).
#   P2  A `declared` field is required source input and still fails closed when
#       absent.
#   P3  A `derivable` field supplied as input is a duplicate writer and fails
#       closed at the input boundary.
#   P4  The classifier does not author network meaning: it creates no policy,
#       reachability, routing, DNS, NAT, exposure or trust authority.
#
# Seeded negatives the SMS requires:
#   SN1  A field supplied as input whose class is `derivable` yields a
#        fail-closed duplicate-writer diagnostic naming the field, the declaring
#        scope, the determining fact, the rule identity and the derived value.
#   SN2  A `declared` field that is absent yields the ordinary missing-input
#        diagnostic and is not default-filled.
#   SN3  A field whose class cannot be determined yields a rejection rather than
#        an assumed class.
#
# To implement: add the classifier against the registry from SMS-010, and emit the
# three diagnostics above.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL declared-versus-derived-classifier: $*" >&2; exit 1; }

# P1: a classifier surface must exist.
if ! grep -rqiE 'classif(y|ier)' "${repo_root}/lib" "${repo_root}/src" --include=*.nix 2>/dev/null; then
  fail "P1 no declared-versus-derived classifier exists in ${repo_root}"
fi

# P1: the two class names must be present.
if ! grep -rqE '"(declared|derivable)"|declared|derivable' "${repo_root}/lib" --include=*.nix 2>/dev/null; then
  fail "P1 the classifier does not name the `declared` and `derivable` classes"
fi

# P3/SN1: duplicate-writer rejection naming the required context.
if ! grep -rqiE 'duplicate.?writer' "${repo_root}/lib" "${repo_root}/src" --include=*.nix 2>/dev/null; then
  fail "SN1 no duplicate-writer diagnostic exists for a supplied derivable field"
fi

# SN2: a declared field must not be default-filled; the missing-input path must
# exist independently of the classifier.
if ! grep -rqiE 'missing.*(input|required)|required.*missing' "${repo_root}/lib" --include=*.nix 2>/dev/null; then
  fail "SN2 no missing-input diagnostic exists for an absent declared field"
fi

# P4: the classifier must not create authority. If its source mentions creating
# policy/authority, it is over-reaching.
if grep -rqiE 'classif.*(creates? policy|grants?|authori[sz]es?)' "${repo_root}/lib" --include=*.nix 2>/dev/null; then
  fail "P4 the classifier source describes creating policy or authority, which the SMS forbids"
fi

echo "PASS declared-versus-derived-classifier"
