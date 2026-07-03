#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-030-HDS-010-SDS-040-SMS-010
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRATCH_ROOT="${TMPDIR:-/tmp}"
tmp_dir="$(mktemp -d "${SCRATCH_ROOT%/}/fs030-sds040-platform-independence.XXXXXX")"
trap 'rm -rf "$tmp_dir"' EXIT

fail() {
  echo "FAIL FS-030-HDS-010-SDS-040-SMS-010: $*" >&2
  exit 1
}

write_site_override() {
  local output="$1"
  local extra="$2"

  cat >"$output" <<NIX
let
  base = import ${ROOT}/tests/fixtures/single-uplink.nix;
in
base // {
  esp0xdeadbeef = base.esp0xdeadbeef // {
    "site-a" = base.esp0xdeadbeef."site-a" // {
${extra}
    };
  };
}
NIX
}

expect_compile_failure() {
  local label="$1"
  local input="$2"
  local expected_code="$3"
  local expected_field="$4"
  local out="${tmp_dir}/${label}.out"
  local err="${tmp_dir}/${label}.err"

  set +e
  nix run "$ROOT#compile" -- "$input" >"$out" 2>"$err"
  local rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    echo "compiled output:" >&2
    cat "$out" >&2
    fail "${label} compiled successfully"
  fi

  grep -Fq "$expected_code" "$err" \
    || { cat "$err" >&2; fail "${label} did not emit ${expected_code}"; }
  grep -Fq "$expected_field" "$err" \
    || { cat "$err" >&2; fail "${label} did not name ${expected_field}"; }

  if jq -e 'has("sites") or has("meta")' "$out" >/dev/null 2>&1; then
    cat "$out" >&2
    fail "${label} produced a behavior artifact after rejection"
  fi

  echo "PASS ${label}: compiler failed closed with ${expected_code}"
}

expect_eval_failure() {
  local label="$1"
  local expr="$2"
  local expected_code="$3"
  local expected_field="$4"
  local log="${tmp_dir}/${label}.log"

  set +e
  nix eval --impure --expr "$expr" >"$log" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    cat "$log" >&2
    fail "${label} eval succeeded"
  fi
  grep -Fq "$expected_code" "$log" \
    || { cat "$log" >&2; fail "${label} did not emit ${expected_code}"; }
  grep -Fq "$expected_field" "$log" \
    || { cat "$log" >&2; fail "${label} did not name ${expected_field}"; }

  echo "PASS ${label}: validator failed closed with ${expected_code}"
}

compiled_json="${tmp_dir}/single-uplink.json"
nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/single-uplink.nix" >"$compiled_json"

jq -e '
  def has_forbidden_key:
    objects
    | keys[]
    | IN(
        "bridgeName",
        "bridgeNames",
        "hostBridge",
        "hostUplink",
        "vlan",
        "vlanId",
        "renderer",
        "rendererTarget",
        "deploymentPlatform",
        "platform",
        "platformTarget",
        "containerRuntime",
        "nftablesChain",
        "systemdUnit",
        "ciscoCli",
        "junosConfig",
        "deviceConfig",
        "platformSyntax",
        "rendererSyntax"
      );
  [.. | has_forbidden_key | select(.)] | length == 0
' "$compiled_json" >/dev/null \
  || { jq '[.. | objects | with_entries(select(.key | test("bridgeName|bridgeNames|hostBridge|hostUplink|vlan|vlanId|renderer|rendererTarget|deploymentPlatform|platform|platformTarget|containerRuntime|nftablesChain|systemdUnit|ciscoCli|junosConfig|deviceConfig|platformSyntax|rendererSyntax")))] | map(select(. != {}))' "$compiled_json" >&2; fail "positive compiled output leaks platform-specific fields"; }

echo "PASS positive: compiler output contains no platform-specific field keys"

renderer_input="${tmp_dir}/renderer-selector.nix"
write_site_override "$renderer_input" '      renderer = "nixos";'
expect_compile_failure \
  "renderer-selector" \
  "$renderer_input" \
  "E_PLATFORM_INDEPENDENCE_SOURCE_FIELD" \
  "renderer"

bridge_input="${tmp_dir}/bridge-name.nix"
write_site_override "$bridge_input" '      bridgeName = "br0";'
expect_compile_failure \
  "bridge-name" \
  "$bridge_input" \
  "E_PLATFORM_INDEPENDENCE_SOURCE_FIELD" \
  "bridgeName"

expect_compile_failure \
  "substrate-technology-selector" \
  "$ROOT/tests/negative/intent-source-boundary-realization-technology.nix" \
  "E_INTENT_SOURCE_BOUNDARY_REALIZATION_TECHNOLOGY" \
  "hatProviderFixture.technology"

base_expr='
let
  flake = builtins.getFlake "path:'"$ROOT"'";
  lib = flake.inputs.nixpkgs.lib;
  platformIndependence = import "'"$ROOT"'/lib/stages/validate-platform-independence.nix" { inherit lib; };
in
'

expect_eval_failure \
  "compiler-output-renderer-leak" \
  "${base_expr} platformIndependence.validateOutput \"seeded-output\" { renderer = \"nixos\"; tenants = [ ]; services = [ ]; relations = [ ]; trafficPaths = [ ]; }" \
  "E_PLATFORM_INDEPENDENCE_OUTPUT_LEAK" \
  "renderer"

expect_eval_failure \
  "compiler-output-platform-syntax-leak" \
  "${base_expr} platformIndependence.validateOutput \"seeded-output\" { nftablesChain = \"forward\"; tenants = [ ]; services = [ ]; relations = [ ]; trafficPaths = [ ]; }" \
  "E_PLATFORM_INDEPENDENCE_OUTPUT_LEAK" \
  "nftablesChain"

echo "PASS FS-030-HDS-010-SDS-040-SMS-010 platform independence contract"
