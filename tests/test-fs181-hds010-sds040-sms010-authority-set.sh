#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-181-HDS-010-SDS-040-SMS-010
# GAMP-SCOPE: control-module-construction
# CMC construction test: Rendered authority set conformance
# Proves every relation emitted by the compiler carries a traceable
# authority identifier, and the authority set is self-consistent.

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TMPDIR="${TMPDIR:-/tmp}"
work_dir="$(mktemp -d "${TMPDIR%/}/fs181-auth-set.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

json_file="${work_dir}/single-wan.json"
nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/single-uplink.nix" >"$json_file"

echo "=== Positive: every relation has an authority identifier (source.id) ==="
relation_count="$(jq '[.sites.esp0xdeadbeef."site-a".relations[] | select(.source.id != null and .source.id != "")] | length' "$json_file")"
total_relations="$(jq '.sites.esp0xdeadbeef."site-a".relations | length' "$json_file")"

if [[ "$relation_count" != "$total_relations" ]]; then
  echo "FAIL: ${total_relations} relations but only ${relation_count} have source.id" >&2
  jq '[.sites.esp0xdeadbeef."site-a".relations[] | select(.source.id == null or .source.id == "")]' "$json_file" >&2
  exit 1
fi
echo "OK: all ${total_relations} relations carry authority identifiers"

echo "=== Positive: every relation has source.sourceAudit with correct authority ==="
audited_count="$(jq '[.sites.esp0xdeadbeef."site-a".relations[] | select(.source.sourceAudit.authority == "network-compiler")] | length' "$json_file")"
if [[ "$audited_count" != "$total_relations" ]]; then
  echo "FAIL: ${total_relations} relations but only ${audited_count} have network-compiler authority audit" >&2
  jq '[.sites.esp0xdeadbeef."site-a".relations[] | select(.source.sourceAudit.authority != "network-compiler")]' "$json_file" >&2
  exit 1
fi
echo "OK: all ${total_relations} relations traced to network-compiler authority"

echo "=== Positive: every relation has source.sourceAudit.sourceClass == user-intent ==="
intent_count="$(jq '[.sites.esp0xdeadbeef."site-a".relations[] | select(.source.sourceAudit.sourceClass == "user-intent")] | length' "$json_file")"
if [[ "$intent_count" != "$total_relations" ]]; then
  echo "FAIL: ${total_relations} relations but only ${intent_count} have user-intent sourceClass" >&2
  jq '[.sites.esp0xdeadbeef."site-a".relations[] | select(.source.sourceAudit.sourceClass != "user-intent")]' "$json_file" >&2
  exit 1
fi
echo "OK: all ${total_relations} relations are user-intent sourced"

echo "=== Positive: authority identifiers are unique (no duplicate source.id) ==="
dup_count="$(jq '[.sites.esp0xdeadbeef."site-a".relations | group_by(.source.id)[] | select(length > 1)] | length' "$json_file")"
if [[ "$dup_count" != "0" ]]; then
  echo "FAIL: ${dup_count} duplicate authority identifier groups found" >&2
  jq '.sites.esp0xdeadbeef."site-a".relations | group_by(.source.id) | map(select(length > 1))' "$json_file" >&2
  exit 1
fi
echo "OK: all authority identifiers are unique"

echo "=== Positive: trafficPaths reference valid authority identifiers ==="
traffic_relation_ids="$(jq '[.sites.esp0xdeadbeef."site-a".trafficPaths[].relationId] | unique' "$json_file")"
relation_source_ids="$(jq '[.sites.esp0xdeadbeef."site-a".relations[].source.id] | unique' "$json_file")"
orphaned_traffic="$(jq -n --argjson traffic "$traffic_relation_ids" --argjson relations "$relation_source_ids" '$traffic - $relations | length')"
if [[ "$orphaned_traffic" != "0" ]]; then
  echo "FAIL: ${orphaned_traffic} trafficPaths reference non-existent relation IDs" >&2
  jq -n --argjson traffic "$traffic_relation_ids" --argjson relations "$relation_source_ids" '$traffic - $relations' >&2
  exit 1
fi
echo "OK: all trafficPath relationIds resolve to authority identifiers"

echo "=== Seeded negative: nix eval proves missing source audit is rejected ==="
negative_expr='
let
  flake = builtins.getFlake "path:'"$ROOT"'";
  lib = flake.inputs.nixpkgs.lib;
  audit = import "'"$ROOT"'/lib/stages/source-audit.nix" { inherit lib; };
  model = {
    tenants = [ { name = "mgmt"; } ];
    services = [ ];
    isolationDecisions = [ ];
    ipv6 = { };
    relations = [
      {
        id = "test-allow-mgmt-to-wan";
        priority = 100;
        from = { kind = "tenant"; name = "mgmt"; };
        to = { kind = "external"; uplinks = [ "wan" ]; };
        trafficType = "any";
        action = "allow";
        source = {
          id = "test-allow-mgmt-to-wan";
          kind = "relation";
          priority = 100;
          # sourceAudit intentionally omitted — MISSING_AUTHORITY_ID negative
        };
      }
    ];
    trafficPaths = [ ];
    overlayAttachments = { };
    overlayAddressPools = { };
    hostNatIngress = { };
  };
in
  audit.validate "neg-test" model
'

set +e
nix eval --impure --expr "$negative_expr" >"${work_dir}/neg1.txt" 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: seeded negative (missing authority audit) was not rejected" >&2
  cat "${work_dir}/neg1.txt" >&2
  exit 1
fi

if ! grep -q "E_COMPILER_BEHAVIOR_SOURCE_AUDIT" "${work_dir}/neg1.txt"; then
  echo "FAIL: seeded negative did not produce E_COMPILER_BEHAVIOR_SOURCE_AUDIT" >&2
  cat "${work_dir}/neg1.txt" >&2
  exit 1
fi
echo "OK: module correctly rejects relation without sourceAudit (MISSING_AUTHORITY_ID-equivalent)"

echo "PASS: FS-181-HDS-010-SDS-040-SMS-010 authority-set conformance construction test"
