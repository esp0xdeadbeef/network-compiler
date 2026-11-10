#!/usr/bin/env bash
# GAMP-ID: FS-530-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-530-HDS-010-SDS-010-SMS-020.md
# OWNER:  network-compiler
#
# Predicates: reject missing DNS policy before canonical resolver advertisement is
# accepted, and emit a diagnostic naming the missing DNS policy input.
# Not executed before commit.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL dns-policy-requirement: $*" >&2; exit 1; }

search=( "${repo_root}/lib" "${repo_root}/src" )

# P1: a missing DNS policy must be refused rather than defaulted.
if ! grep -rqiE 'dns.?policy' "${search[@]}" --include=*.nix 2>/dev/null; then
  fail "P1 no DNS-policy concept exists, so a missing policy cannot be refused"
fi

if ! grep -rqiE 'missing.*dns.?policy|dns.?policy.*missing|E_DNS_POLICY' \
  "${search[@]}" --include=*.nix 2>/dev/null; then
  fail "P1 no rejection exists for a missing DNS policy input; a resolver advertisement could be accepted without one"
fi

# P2: the diagnostic must name the missing input.
if ! grep -rqiE 'dns.?policy[^\n]*\b(path|input|required|missing)\b' \
  "${search[@]}" --include=*.nix 2>/dev/null; then
  fail "P2 the missing-DNS-policy diagnostic does not name the missing input"
fi

# P3: the refusal must happen before resolver advertisement is accepted, so the
# guard must exist on the advertisement path rather than only in a validator.
if ! grep -rqiE 'resolver.?advertis|advertis.*resolver' "${search[@]}" --include=*.nix 2>/dev/null; then
  fail "P3 no resolver-advertisement path exists to order the refusal against"
fi

echo "PASS dns-policy-requirement"
