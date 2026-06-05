#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-080-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
scratch_root="${TMPDIR:-/tmp}"
work_dir="$(mktemp -d "${scratch_root%/}/fs080-missing-ambiguous.XXXXXX")"
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

missing_output="$work_dir/missing-upstream-selector.txt"
missing_json="$(extract_json_error "$ROOT/tests/negative/multi-wan-missing-upstream-selector.nix" "$missing_output")"

assert_json_field \
  "missing fact must raise E_TOPO_MISSING_UPSTREAM_SELECTOR" \
  '.code == "E_TOPO_MISSING_UPSTREAM_SELECTOR"' \
  "$missing_json"
assert_json_field \
  "missing fact must name affected scope" \
  '.site == "badsite"' \
  "$missing_json"
assert_json_field \
  "missing fact must name owning input path" \
  '.path == ["topology", "nodes"]' \
  "$missing_json"
assert_json_field \
  "missing fact must explain the required correction" \
  '.hints | index("Add a node with role = \"upstream-selector\".") != null' \
  "$missing_json"

ambiguous_output="$work_dir/duplicate-uplink-name.txt"
ambiguous_json="$(extract_json_error "$ROOT/tests/negative/duplicate-uplink-name.nix" "$ambiguous_output")"

assert_json_field \
  "ambiguous fact must raise E_UPLINK_NAME_NOT_UNIQUE" \
  '.code == "E_UPLINK_NAME_NOT_UNIQUE"' \
  "$ambiguous_json"
assert_json_field \
  "ambiguous fact must name affected scope" \
  '.site == "badsite"' \
  "$ambiguous_json"
assert_json_field \
  "ambiguous fact must name owning input path" \
  '.path == ["topology", "nodes"]' \
  "$ambiguous_json"
assert_json_field \
  "ambiguous fact must explain the ambiguity" \
  '.message == "uplink name '\''wan'\'' must be unique across all core nodes in the site"' \
  "$ambiguous_json"
assert_json_field \
  "ambiguous fact must explain the required correction" \
  '.hints | index("Rename one of the duplicate uplinks so external names stay unambiguous.") != null' \
  "$ambiguous_json"

echo "PASS: FS-080 focused SMT evidence proves missing and ambiguous compiler facts fail with structured diagnostics"
