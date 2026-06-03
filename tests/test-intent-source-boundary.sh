#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-COMP-FS800-INTENT-SOURCE-BOUNDARY-001
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"

run_negative() {
  local fixture="$1"
  local code="$2"
  local out
  out="$(mktemp)"

  set +e
  nix run "$ROOT#compile" -- "$ROOT/tests/negative/${fixture}.nix" >"$out" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL intent source boundary: ${fixture} compiled successfully" >&2
    cat "$out" >&2
    rm -f "$out"
    exit 1
  fi

  if ! grep -q "$code" "$out"; then
    echo "FAIL intent source boundary: ${fixture} did not emit ${code}" >&2
    cat "$out" >&2
    rm -f "$out"
    exit 1
  fi

  rm -f "$out"
}

run_negative intent-source-boundary-side-channel E_INTENT_SOURCE_BOUNDARY_SIDE_CHANNEL
run_negative intent-source-boundary-realization-technology E_INTENT_SOURCE_BOUNDARY_REALIZATION_TECHNOLOGY

echo "PASS intent-source-boundary"
