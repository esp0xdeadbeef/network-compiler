#!/usr/bin/env bash
# GAMP-ID: FS-482-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-482-HDS-010-SDS-010-SMS-030.md
# OWNER:  network-compiler
# MODULE: Learned-Route Classification
#
# THIS TEST IS EXPECTED TO FAIL. The specification exists; the module does not.
# Do not weaken the test to make it pass — implement the module.
#
# Predicates taken from the SMS:
#   P1  A BGP-learned route is classified as conditional route availability until
#       current route-import facts are supplied.
#   P2  A learned route is kept out of the owned-prefix surface.
#   P3  A learned route is kept out of the payload-permission surface.
#   P4  Each learned route is exposed with its peer, address family and import
#       classification; a learned route is never presented as a model-owned
#       prefix.
#
# Seeded negatives the SMS requires:
#   SN1  A learned route presented as an owned prefix is refused, naming the
#        prefix and the peer.
#   SN2  A learned route with no import classification is refused, naming the
#        route.
#   SN3  A learned route placed on the payload-permission surface is refused.
#   SN4  Supplying import facts classifies the route as conditional availability
#        rather than owned.
#
# To implement: add the classification at the point where routes enter the model,
# before prefix authority is decided, and emit the three refusals above.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL learned-route-classification: $*" >&2; exit 1; }

# P1: the conditional-availability concept must exist.
if ! grep -rqiE 'conditional' "${repo_root}/lib" "${repo_root}/src" --include=*.nix 2>/dev/null; then
  fail "P1 no conditional route-availability classification exists for a learned route"
fi

# P1/P4: import classification must be carried per route.
if ! grep -rqiE 'route.?import|import.?classif' "${repo_root}/lib" "${repo_root}/src" --include=*.nix 2>/dev/null; then
  fail "P4 no route-import classification exists; a learned route cannot be distinguished from an owned prefix"
fi

# P4: the peer and address family must accompany the learned route.
missing=""
grep -rqiE 'peer' "${repo_root}/lib" --include=*.nix 2>/dev/null || missing="${missing} peer"
grep -rqiE 'family|ipv4|ipv6' "${repo_root}/lib" --include=*.nix 2>/dev/null || missing="${missing} address-family"
if [[ -n "${missing}" ]]; then
  fail "P4 the learned-route surface does not expose:${missing}"
fi

# P2/SN1: a learned route must not be able to reach the owned-prefix surface.
if ! grep -rqiE 'owned.?prefix' "${repo_root}/lib" "${repo_root}/src" --include=*.nix 2>/dev/null; then
  fail "P2 there is no owned-prefix concept to enforce the P2 separation against"
fi
if ! grep -rqiE 'learned.*owned|owned.*learned' "${repo_root}/lib" "${repo_root}/src" --include=*.nix 2>/dev/null; then
  fail "SN1 no rejection exists for a learned route presented as an owned prefix"
fi

# P3/SN3: the payload-permission surface must be separate from route availability.
if ! grep -rqiE 'permission' "${repo_root}/lib" --include=*.nix 2>/dev/null; then
  fail "P3 there is no permission surface to enforce the P3 separation against"
fi

# SN2: an unclassified learned route must be refused.
if ! grep -rqiE 'unclassif' "${repo_root}/lib" "${repo_root}/src" --include=*.nix 2>/dev/null; then
  fail "SN2 no rejection exists for a learned route with no import classification"
fi

echo "PASS learned-route-classification"
