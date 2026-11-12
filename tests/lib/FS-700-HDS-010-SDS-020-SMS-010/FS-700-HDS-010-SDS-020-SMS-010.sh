#!/usr/bin/env bash
# GAMP-ID: FS-700-HDS-010-SDS-020-SMS-010
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-700-HDS-010-SDS-020-SMS-010.md
# OWNER:  network-compiler
#
# Predicates: each source is assigned exactly one source class, and a source that
# mixes modeled behavior with realization facts is rejected.
#
# Behavioural: compiles a clean intent, then the same intent with a realization-only
# field injected into the behavior source, and requires the compiler to reject it by
# diagnostic code and field path.
#
# Not executed before commit.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

require_cmd() { command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }; }
require_cmd nix
require_cmd jq

fail() { echo "FAIL source-class-assignment: $*" >&2; exit 1; }

flake_input_path() {
  local input="$1"
  if [[ "${input}" == "network-labs" && -n "${NETWORK_LABS_PATH:-}" ]]; then realpath "${NETWORK_LABS_PATH}"; return; fi
  nix flake archive --json "path:${repo_root}" | jq -er ".inputs[\"${input}\"].path"
}

example_dir="$(flake_input_path network-labs)/examples/single-wan"
intent="${example_dir}/intent.nix"
inventory="${example_dir}/inventory-nixos.nix"
tmp_dir="$(mktemp -d)"; trap 'rm -rf "${tmp_dir}"' EXIT

# `compilePath` takes the intent path as a single string and runs the whole
# pipeline on it (flake.nix:163: `compilePath = valueOrPath: compile (readValue
# valueOrPath)`). It was called here as `compileAndBuildFromPaths { inputPath;
# inventoryPath; }`, which is the *control-plane model's* API -- this repository
# exposes neither that name nor an inventory parameter, so the case failed with
#   error: attribute 'compileAndBuildFromPaths' missing
# before compiling anything. The sibling case FS-482 uses the form below.
compile() {
  nix eval --no-write-lock-file --impure --json --expr '
    let
      f = builtins.getFlake "'"path:${repo_root}"'";
    in f.libBySystem."x86_64-linux".compilePath "'"$1"'"
  '
}

# P1: a clean behavior source compiles, so a rejection below is attributable to the
# injected realization fact and not to a broken fixture.
compile "${intent}" >"${tmp_dir}/clean.json" 2>"${tmp_dir}/clean.err" \
  || fail "P1 the unmutated intent does not compile:
$(cat "${tmp_dir}/clean.err")"

# SN1: a realization-only field injected into the behavior source must be rejected
# as a mixed source, naming the diagnostic and the field path.
mixed="${tmp_dir}/intent-mixed.nix"
cat >"${mixed}" <<EOF
let
  base = import ${intent};
  site = base.esp0xdeadbeef."site-a";
in
base // {
  esp0xdeadbeef = base.esp0xdeadbeef // {
    "site-a" = site // {
      upstreamEmulation = { provider = "isp"; };
    };
  };
}
EOF

set +e
compile "${mixed}" >"${tmp_dir}/mixed.out" 2>"${tmp_dir}/mixed.err"
rc=$?
set -e

((rc != 0)) || fail "SN1 a realization-only field injected into the behavior source compiled, so the source classes are not separated"
grep -q 'E_INTENT_SOURCE_BOUNDARY_SIDE_CHANNEL' "${tmp_dir}/mixed.err" \
  || fail "SN1 the rejection did not carry E_INTENT_SOURCE_BOUNDARY_SIDE_CHANNEL:
$(cat "${tmp_dir}/mixed.err")"
grep -q 'upstreamEmulation' "${tmp_dir}/mixed.err" \
  || fail "SN1 the rejection did not name the offending field
$(cat "${tmp_dir}/mixed.err")"
[[ -s "${tmp_dir}/mixed.out" ]] && fail "SN1 the rejected run released an artifact"

echo "PASS source-class-assignment"
