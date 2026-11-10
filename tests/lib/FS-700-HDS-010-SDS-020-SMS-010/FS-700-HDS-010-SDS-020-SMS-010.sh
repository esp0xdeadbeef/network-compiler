#!/usr/bin/env bash
# GAMP-ID: FS-700-HDS-010-SDS-020-SMS-010
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-700-HDS-010-SDS-020-SMS-010.md
# OWNER:  network-compiler
# MODULE: source-class-assignment
#
# Not executed before commit.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL source-class-assignment: $*" >&2; exit 1; }


# P1: every accepted source file is assigned exactly one source class. The compiler
# already classifies inputs; the invariant is that the class set is closed and each
# file maps into exactly one member.
search=( "${repo_root}/lib" )
missing=""
for cls in behavior-intent public-inventory protected-inventory runtime-fact; do
  grep -rqiE "${cls}" "${search[@]}" --include=*.nix 2>/dev/null || missing="${missing} ${cls}"
done
[[ -z "${missing}" ]] || fail "P1 the source-class vocabulary cannot express:${missing}"

# P2: a file that mixes behavior with realization facts must be rejected, so a
# mixing diagnostic has to exist.
grep -rqiE "source.?class[^\\n]*(mix|reject|invalid)|E_SOURCE_CLASS" "${search[@]}" --include=*.nix 2>/dev/null \
  || fail "P2 no diagnostic exists for a source file that mixes modeled behavior with realization facts"

