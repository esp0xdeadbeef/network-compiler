#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-030-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"

run_negative() {
  local fixture="$1"
  local code="$2"
  local field_path="$3"
  local out err
  out="$(mktemp)"
  err="$(mktemp)"

  set +e
  nix run "$ROOT#compile" -- "$ROOT/tests/negative/${fixture}.nix" >"$out" 2>"$err"
  local rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL intent source boundary: ${fixture} compiled successfully" >&2
    cat "$out" >&2
    cat "$err" >&2
    rm -f "$out" "$err"
    exit 1
  fi

  if ! grep -Fq "$code" "$err"; then
    echo "FAIL intent source boundary: ${fixture} did not emit ${code}" >&2
    cat "$out" >&2
    cat "$err" >&2
    rm -f "$out" "$err"
    exit 1
  fi

  if ! grep -Fq "$field_path" "$err"; then
    echo "FAIL intent source boundary: ${fixture} did not name field ${field_path}" >&2
    cat "$out" >&2
    cat "$err" >&2
    rm -f "$out" "$err"
    exit 1
  fi

  if jq -e 'has("sites") or has("meta")' "$out" >/dev/null 2>&1; then
    echo "FAIL intent source boundary: ${fixture} produced a behavior-model artifact" >&2
    cat "$out" >&2
    cat "$err" >&2
    rm -f "$out" "$err"
    exit 1
  fi

  rm -f "$out" "$err"
}

run_positive() {
  local fixture="$1"
  local out
  out="$(mktemp)"
  nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/${fixture}.nix" >"$out"
  jq -e 'has("sites") and has("meta")' "$out" >/dev/null || {
    echo "FAIL intent source boundary: clean fixture ${fixture} did not produce behavior model" >&2
    cat "$out" >&2
    rm -f "$out"
    exit 1
  }
  rm -f "$out"
}

run_negative intent-source-boundary-side-channel E_INTENT_SOURCE_BOUNDARY_SIDE_CHANNEL upstreamEmulation
run_negative intent-source-boundary-realization-technology E_INTENT_SOURCE_BOUNDARY_REALIZATION_TECHNOLOGY hatProviderFixture.technology
run_positive single-uplink

echo "PASS intent-source-boundary"
