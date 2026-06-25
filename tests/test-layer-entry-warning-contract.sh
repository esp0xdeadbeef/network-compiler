#!/usr/bin/env bash
# GAMP-ID: FS-166-HDS-010-SDS-010-SMS-900
# GAMP-SCOPE: software-module-test; compiler layer-entry warning contract
set -euo pipefail

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d "${TMPDIR:-/tmp}/network-compiler-layer-entry.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "FAIL layer-entry-warning-contract: $*" >&2
  exit 1
}

nix run --no-warn-dirty --no-write-lock-file "path:${ROOT}#layer-entry-warnings" -- \
  forwarding-model-input >"${tmp_dir}/nfm-entry.json" 2>"${tmp_dir}/nfm-entry.err"

jq -e '
  .entryBoundary == "forwarding-model-input"
  and .skippedUpstreamLayers == [ "intent-source", "network-compiler" ]
  and ([.warnings[].code] == [
    "WARN_LAYER_ENTRY_SKIPS_NETWORK_LABS_INTENT_SOURCE",
    "WARN_LAYER_ENTRY_SKIPS_NETWORK_COMPILER"
  ])
' "${tmp_dir}/nfm-entry.json" >/dev/null \
  || fail "NFM-entry warning payload does not identify skipped compiler coverage"

grep -Fq "WARNING: WARN_LAYER_ENTRY_SKIPS_NETWORK_COMPILER" "${tmp_dir}/nfm-entry.err" \
  || fail "NFM-entry stderr did not surface the compiler skip warning"

nix run --no-warn-dirty --no-write-lock-file "path:${ROOT}#layer-entry-warnings" -- \
  intent-source >"${tmp_dir}/intent-source.json" 2>"${tmp_dir}/intent-source.err"

jq -e '
  .entryBoundary == "intent-source"
  and .skippedUpstreamLayers == []
  and .warnings == []
' "${tmp_dir}/intent-source.json" >/dev/null \
  || fail "intent-source boundary should not warn or skip upstream compiler coverage"

[[ ! -s "${tmp_dir}/intent-source.err" ]] \
  || fail "intent-source boundary unexpectedly emitted warnings"

echo "PASS layer-entry-warning-contract"
