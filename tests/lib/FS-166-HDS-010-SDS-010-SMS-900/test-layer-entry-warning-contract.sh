#!/usr/bin/env bash
# GAMP-ID: FS-166-HDS-010-SDS-010-SMS-900
# GAMP-SCOPE: software-module-test; compiler layer-entry warning contract
set -euo pipefail

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
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
  and .repo == "network-compiler"
  and .repoSkipped == true
  and .inputTreatment == "pass-through"
  and .skippedUpstreamLayers == [ "intent-source", "network-compiler" ]
  and ([.warnings[].code] == [
    "WARN_LAYER_ENTRY_SKIPS_NETWORK_LABS_INTENT_SOURCE",
    "WARN_LAYER_ENTRY_SKIPS_NETWORK_COMPILER"
  ])
' "${tmp_dir}/nfm-entry.json" >/dev/null \
  || fail "NFM-entry warning payload does not identify skipped compiler coverage"

grep -Fq "WARNING: WARN_LAYER_ENTRY_SKIPS_NETWORK_COMPILER" "${tmp_dir}/nfm-entry.err" \
  || fail "NFM-entry stderr did not surface the compiler skip warning"

nix eval --impure --json --expr "
  let
    flake = builtins.getFlake \"path:${ROOT}\";
  in
    flake.libBySystem.\${builtins.currentSystem}.layerEntryEnvelope {
      entryBoundary = \"forwarding-model-input\";
      input = {
        pocKind = \"synthetic-forwarding-model-input\";
        sites = { lab = { }; };
      };
    }
" >"${tmp_dir}/nfm-entry-envelope.json"

jq -e '
  .entryBoundary == "forwarding-model-input"
  and .repo == "network-compiler"
  and .repoSkipped == true
  and .inputTreatment == "pass-through"
  and .normalizedTo == "nix-attrset"
  and .input == .output
  and .input.pocKind == "synthetic-forwarding-model-input"
  and ([.warnings[].code] == [
    "WARN_LAYER_ENTRY_SKIPS_NETWORK_LABS_INTENT_SOURCE",
    "WARN_LAYER_ENTRY_SKIPS_NETWORK_COMPILER"
  ])
' "${tmp_dir}/nfm-entry-envelope.json" >/dev/null \
  || fail "NFM-entry envelope did not pass through compiler input with warnings"

nix run --no-warn-dirty --no-write-lock-file "path:${ROOT}#layer-entry-warnings" -- \
  intent-source >"${tmp_dir}/intent-source.json" 2>"${tmp_dir}/intent-source.err"

jq -e '
  .entryBoundary == "intent-source"
  and .repo == "network-compiler"
  and .repoSkipped == false
  and .inputTreatment == "consume-or-normalize"
  and .skippedUpstreamLayers == []
  and .warnings == []
' "${tmp_dir}/intent-source.json" >/dev/null \
  || fail "intent-source boundary should not warn or skip upstream compiler coverage"

[[ ! -s "${tmp_dir}/intent-source.err" ]] \
  || fail "intent-source boundary unexpectedly emitted warnings"

echo "PASS layer-entry-warning-contract"
