#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-030-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
SCRATCH_ROOT="${TMPDIR:-/tmp}"
work_dir="$(mktemp -d "${SCRATCH_ROOT%/}/compiler-source-audit.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

compiled_json="${work_dir}/single-wan.json"
nix run "$ROOT#compile" -- labs:examples/single-wan/intent.nix >"$compiled_json"

jq -e '
  .sites.esp0xdeadbeef."site-a" as $site
  | ($site.sourceAudit.behavior // []) as $audit
  | ($audit | length) > 0
  and ([$audit[] | select(.sourceClass != "user-intent" or .authority != "network-compiler")] | length == 0)
  and ($audit[] | select(.outputPath == ["relations", 0] and .sourcePath == ["communicationContract", "relations", 0]))
  and ($audit[] | select(.outputPath == ["trafficPaths", 0]))
' "$compiled_json" >/dev/null || {
  echo "FAIL compiler behavior source audit: compiled output lacks user-intent audit records" >&2
  jq '.sites.esp0xdeadbeef."site-a".sourceAudit' "$compiled_json" >&2
  exit 1
}

run_eval_negative() {
  local name="$1"
  local expr="$2"
  local detailCheck="$3"
  local out="${work_dir}/${name}.txt"

  set +e
  nix eval --impure --expr "$expr" >"$out" 2>&1
  local rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL compiler behavior source audit: ${name} eval succeeded" >&2
    cat "$out" >&2
    exit 1
  fi

  if ! grep -q "E_COMPILER_BEHAVIOR_SOURCE_AUDIT" "$out"; then
    echo "FAIL compiler behavior source audit: ${name} missing diagnostic" >&2
    cat "$out" >&2
    exit 1
  fi

  if [[ -n "$detailCheck" ]]; then
    if ! grep -q "$detailCheck" "$out"; then
      echo "FAIL compiler behavior source audit: ${name} missing expected detail \"$detailCheck\"" >&2
      cat "$out" >&2
      exit 1
    fi
  fi
}

base_expr='
let
  flake = builtins.getFlake "path:'"$ROOT"'";
  lib = flake.inputs.nixpkgs.lib;
  audit = import "'"$ROOT"'/lib/stages/source-audit.nix" { inherit lib; };
  model = {
    tenants = [ { name = "mgmt"; } ];
    services = [ ];
    ipv6 = { };
    relations = [ ];
    overlayAttachments = { };
    overlayAddressPools = { };
    trafficPaths = [ ];
    hostNatIngress = { };
  };
in
'

# SN1: missing behavior audit entirely
run_eval_negative "missing-audit" "${base_expr} audit.validate \"audit-test\" model" "lacks a user-intent"
# SN2: non-intent sourceClass = "inventory"
run_eval_negative "non-intent-inventory" "${base_expr} audit.validate \"audit-test\" (model // { sourceAudit.behavior = [ { outputPath = [ \"tenants\" 0 ]; sourceClass = \"inventory\"; sourcePath = [ \"inventory\" ]; authority = \"network-compiler\"; } ]; })" 'inventory'
# SN3: non-intent sourceClass = "realization" (seeded negative requirement)
run_eval_negative "non-intent-realization" "${base_expr} audit.validate \"audit-test\" (model // { sourceAudit.behavior = [ { outputPath = [ \"tenants\" 0 ]; sourceClass = \"realization\"; sourcePath = [ \"inventory\" ]; authority = \"network-compiler\"; } ]; })" 'realization'
# SN4: non-compiler authority
run_eval_negative "non-compiler-authority" "${base_expr} audit.validate \"audit-test\" (model // { sourceAudit.behavior = [ { outputPath = [ \"tenants\" 0 ]; sourceClass = \"user-intent\"; sourcePath = [ \"segments\" \"tenants\" \"mgmt\" ]; authority = \"network-control-plane-model\"; } ]; })" 'network-control-plane-model'

echo "PASS compiler-behavior-source-audit"
