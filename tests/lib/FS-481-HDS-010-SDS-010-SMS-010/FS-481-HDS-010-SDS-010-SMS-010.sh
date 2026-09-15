#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-481-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
# Construction test: a required routing behavior must be satisfiable by the
# modeled selection, or the compiler fails closed (FS-481).

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
scratch_root="${TMPDIR:-/tmp}"
work_dir="$(mktemp -d "${scratch_root%/}/fs481-behavior.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

extract_json_error() {
  local input_file="$1" output_file="$2"
  set +e
  nix run "$ROOT#compile" -- "$input_file" >"$output_file" 2>&1
  local rc=$?
  set -e
  if [ "$rc" -eq 0 ]; then
    echo "FAIL: expected compiler failure for $input_file" >&2
    cat "$output_file" >&2
    exit 1
  fi
  local json_line
  json_line="$(sed -n 's/^.*error: //p' "$output_file" | tail -n 1)"
  [ -n "$json_line" ] || { echo "FAIL: expected structured JSON diagnostic for $input_file" >&2; cat "$output_file" >&2; exit 1; }
  printf '%s\n' "$json_line"
}

check_negative() {
  local fixture="$1"
  local json
  json="$(extract_json_error "$ROOT/tests/negative/${fixture}" "$work_dir/${fixture}.txt")"
  jq -e '.code == "E_CONTRACT_BEHAVIOR"' <<<"$json" >/dev/null || {
    echo "FAIL ${fixture}: expected E_CONTRACT_BEHAVIOR" >&2; echo "$json" >&2; exit 1; }
  jq -e '(.spec // "") | test("FS-481")' <<<"$json" >/dev/null || {
    echo "FAIL ${fixture}: expected FS-481 in spec" >&2; echo "$json" >&2; exit 1; }
  echo "PASS ${fixture}"
}

check_negative fs481-empty-selection-behavior.nix
check_negative fs481-unknown-behavior.nix
check_negative fs481-equal-cost-no-overlap.nix

# Positive: a satisfiable behavior on an overlapping selection compiles.
set +e
nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/fs481-satisfiable.nix" >"$work_dir/pos.json" 2>"$work_dir/pos.err"
pos_rc=$?
set -e
[ "$pos_rc" -eq 0 ] || { echo "FAIL: satisfiable behavior fixture must compile" >&2; cat "$work_dir/pos.err" >&2; exit 1; }
echo "PASS fs481-satisfiable"

echo "PASS FS-481-HDS-010-SDS-010-SMS-010 selection behavior satisfiability"
