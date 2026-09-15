#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-483-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
# Construction test: a required liveness behavior needs a declared control-plane
# traffic type, or the compiler fails before downstream output (FS-483).

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
scratch_root="${TMPDIR:-/tmp}"
work_dir="$(mktemp -d "${scratch_root%/}/fs483-liveness.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

set +e
nix run "$ROOT#compile" -- "$ROOT/tests/negative/fs483-liveness-without-traffic-type.nix" >"$work_dir/neg.txt" 2>&1
neg_rc=$?
set -e
[ "$neg_rc" -ne 0 ] || { echo "FAIL: liveness without a traffic type must fail closed" >&2; exit 1; }
grep -q "FS-483" "$work_dir/neg.txt" || {
  echo "FAIL: expected an FS-483 diagnostic" >&2; cat "$work_dir/neg.txt" >&2; exit 1; }
echo "PASS fs483-liveness-without-traffic-type"

set +e
nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/fs483-liveness-satisfiable.nix" >"$work_dir/pos.json" 2>"$work_dir/pos.err"
pos_rc=$?
set -e
[ "$pos_rc" -eq 0 ] || {
  echo "FAIL: liveness with a declared control-plane traffic type must compile" >&2; cat "$work_dir/pos.err" >&2; exit 1; }
echo "PASS fs483-liveness-satisfiable"

echo "PASS FS-483-HDS-010-SDS-010-SMS-010 liveness behavior authorization"
