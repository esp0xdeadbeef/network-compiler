#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-081-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test
# Construction test: the compiler rejects superseded intent shapes and names the
# owning specification for each (FS-081 Superseded-Contract Rejection).

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
scratch_root="${TMPDIR:-/tmp}"
work_dir="$(mktemp -d "${scratch_root%/}/fs081-superseded.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

# Collect the structured JSON diagnostic from a failing compile.
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

# check <fixture> <path-json> <spec-substring>
check() {
  local fixture="$1"
  local want_path="$2"
  local want_spec="$3"
  local label
  label="$(basename "$fixture" .nix)"
  local out="$work_dir/${label}.txt"
  local json
  json="$(extract_json_error "$ROOT/tests/negative/${fixture}" "$out")"

  assert_json_field "${label}: raises E_SUPERSEDED_CONTRACT" \
    '.code == "E_SUPERSEDED_CONTRACT"' "$json"
  assert_json_field "${label}: names the affected path ${want_path}" \
    ".path == ${want_path}" "$json"
  assert_json_field "${label}: cites owning spec ${want_spec}" \
    "(.spec // \"\") | test(\"${want_spec}\")" "$json"
}

# Seeded negatives 1-4: removed top-level intent keys, owned by FS-081.
check fs081-legacy-policy.nix '["policy"]' 'FS-081'
check fs081-legacy-internet-mode.nix '["internetMode"]' 'FS-081'
check fs081-legacy-routing-style.nix '["routingStyle"]' 'FS-081'
check fs081-legacy-provider-profile.nix '["providerProfile"]' 'FS-081'

# Seeded negatives 5-6: relation names uplinks, owned by FS-322.
check fs081-legacy-relation-to-uplinks.nix \
  '["communicationContract","relations",0,"to","uplinks"]' 'FS-322'
check fs081-legacy-relation-from-uplinks.nix \
  '["communicationContract","relations",0,"from","uplinks"]' 'FS-322'

# Seeded negatives 7-8: per-uplink routing mode, owned by FS-481.
check fs081-legacy-uplink-egress-mode.nix \
  '["topology","nodes","core","uplinks","wan","egress"]' 'FS-481'
check fs081-legacy-uplink-egress-bgp.nix \
  '["topology","nodes","core","uplinks","wan","egress"]' 'FS-481'

# Seeded negative 9: positive recovery. The current contract (scope offers /
# selects and a bare external relation) must compile.
set +e
nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/current-contract.nix" >"$work_dir/positive.json" 2>"$work_dir/positive.err"
positive_rc=$?
set -e
if [ "$positive_rc" -ne 0 ]; then
  echo "FAIL: current-contract fixture must compile" >&2
  cat "$work_dir/positive.err" >&2
  exit 1
fi
jq -e '.sites != null' "$work_dir/positive.json" >/dev/null || {
  echo "FAIL: current-contract fixture produced no sites" >&2
  exit 1
}

echo "PASS FS-081-HDS-010-SDS-010-SMS-010 superseded-contract rejection"
