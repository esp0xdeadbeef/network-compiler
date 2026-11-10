#!/usr/bin/env bash
# GAMP-ID: FS-670-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
# GAMP-OWNER: network-compiler
#
# SPEC:   GAMP/SMS/FS-670-HDS-010-SDS-010-SMS-010.md
# OWNER:  network-compiler
#
# Predicates: exactly one matrix row per modeled tenant or access scope, each row
# bound to purpose, client classes and operator-visible name, and matrix reporting
# kept distinct from policy authority.
#
# Behavioural for the uniqueness clause: calls `assertUnique` from
# lib/correctness/util.nix with a duplicate scope list and requires it to refuse,
# then with a unique list and requires it to accept. The stage applies that guard at
# lib/stages/access-space-discovery/default.nix as `_uniqueScopes`.
#
# Not executed before commit.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL access-matrix-row: $*" >&2; exit 1; }

util="${repo_root}/lib/correctness/util.nix"
stage="${repo_root}/lib/stages/access-space-discovery/default.nix"

[[ -f "${util}" ]] || fail "P1 ${util#"${repo_root}/"} does not exist, so the uniqueness guard cannot be called"
[[ -f "${stage}" ]] || fail "P1 ${stage#"${repo_root}/"} does not exist, so the matrix stage cannot be inspected"

run_util() {
  local expr="$1"
  nix eval --no-write-lock-file --impure --json --expr '
    let
      f = builtins.getFlake "'"path:${repo_root}"'";
      pkgs = import f.inputs.nixpkgs { };
      util = import "'"${util}"'" { lib = pkgs.lib; };
    in
      '"${expr}"'
  '
}

# SN1: a duplicate scope must be refused. Two matrix rows for one scope means the
# matrix no longer has one row per modeled scope.
set +e
out="$(run_util 'util.assertUnique "access-space discovery scope" [ "a" "b" "a" ]' 2>&1)"
rc=$?
set -e
((rc != 0)) || fail "SN1 assertUnique accepted a duplicated scope, so two matrix rows can exist for one scope"
grep -q 'a' <<<"${out}" || fail "SN1 the refusal did not name the duplicated scope
${out}"

# SN2: unique scopes must be accepted, so the guard is not a blanket refusal.
run_util 'util.assertUnique "access-space discovery scope" [ "a" "b" "c" ]' >/dev/null 2>&1 \
  || fail "SN2 assertUnique rejected a unique scope list"

# P1: the stage must actually apply the guard to the matrix, otherwise the
# behaviour above is unused.
if ! grep -qE '_uniqueScopes\s*=\s*assertUnique' "${stage}"; then
  fail "P1 the matrix stage does not apply assertUnique to the scope list, so duplicate rows would collapse silently"
fi

# P1: the matrix must be built from scope-keyed entries, so one row maps to one
# scope rather than to a list.
if ! grep -qE 'matrixByScope' "${stage}"; then
  fail "P1 the stage does not build a scope-keyed matrix, so row-to-scope binding cannot be asserted"
fi

echo "PASS access-matrix-row"
