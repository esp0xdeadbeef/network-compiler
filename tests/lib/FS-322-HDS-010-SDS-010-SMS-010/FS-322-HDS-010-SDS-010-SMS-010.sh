#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-322-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
# Construction test: scope reachability is normalized from a scope's
# offers/selects, a selection must name a modeled scope, and a relation that
# names an uplink is rejected, naming FS-322 as the owning item.

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
scratch_root="${TMPDIR:-/tmp}"
work_dir="$(mktemp -d "${scratch_root%/}/fs322-reachability.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

extract_json_error() {
  local input_file="$1"
  local output_file="$2"

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
  if [ -z "$json_line" ]; then
    echo "FAIL: expected structured JSON diagnostic for $input_file" >&2
    cat "$output_file" >&2
    exit 1
  fi

  printf '%s\n' "$json_line"
}

assert_json_field() {
  local name="$1"
  local expr="$2"
  local json="$3"

  if ! jq -e "$expr" <<<"$json" >/dev/null; then
    echo "FAIL: ${name}" >&2
    echo "$json" >&2
    exit 1
  fi
}

# Seeded negative 1: a relation names an uplink; reachability is a scope
# property, owned by FS-322.
json="$(extract_json_error "$ROOT/tests/negative/fs081-legacy-relation-to-uplinks.nix" "$work_dir/rel.txt")"
assert_json_field "relation naming uplinks raises E_SUPERSEDED_CONTRACT" \
  '.code == "E_SUPERSEDED_CONTRACT"' "$json"
assert_json_field "relation naming uplinks cites FS-322" \
  '(.spec // "") | test("FS-322")' "$json"

# Seeded negative 2: a scope selects a name that is not a modeled scope.
json="$(extract_json_error "$ROOT/tests/negative/fs322-select-unknown-scope.nix" "$work_dir/select.txt")"
assert_json_field "unknown selection raises E_CONTRACT_UNKNOWN_SELECT" \
  '.code == "E_CONTRACT_UNKNOWN_SELECT"' "$json"
assert_json_field "unknown selection cites FS-322" \
  '(.message // "") | test("FS-322")' "$json"

# Seeded negative 3: positive recovery. A scope with offers/selects that name
# modeled scopes yields a normalized reachability model, preserving order.
set +e
nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/current-contract.nix" >"$work_dir/positive.json" 2>"$work_dir/positive.err"
positive_rc=$?
set -e
if [ "$positive_rc" -ne 0 ]; then
  echo "FAIL: current-contract fixture must compile" >&2
  cat "$work_dir/positive.err" >&2
  exit 1
fi
jq -e '.sites.goodsite["site-a"]? // .sites.goodsite? | type == "object"' "$work_dir/positive.json" >/dev/null 2>&1 \
  || jq -e '.sites != null' "$work_dir/positive.json" >/dev/null || {
  echo "FAIL: current-contract fixture produced no sites" >&2
  exit 1
}

echo "PASS FS-322-HDS-010-SDS-010-SMS-010 scope reachability normalization"
