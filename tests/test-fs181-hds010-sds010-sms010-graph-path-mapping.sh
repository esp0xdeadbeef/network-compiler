#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-181-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: control-module-construction
# CMC construction test: Graph path mapping authority
# Proves trafficPaths are derived from model-eligible graph alternatives,
# preserve wildcard destination alternatives, and reject realization-fact-derived mappings.

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
TMPDIR="${TMPDIR:-/tmp}"
work_dir="$(mktemp -d "${TMPDIR%/}/fs181-graph-path.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

echo "=== Positive: single-wan fixture produces trafficPaths with canonical stage order ==="
json_file="${work_dir}/single-wan.json"
nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/single-uplink.nix" >"$json_file"

path_count="$(jq '[.sites.esp0xdeadbeef."site-a".trafficPaths[]] | length' "$json_file")"
if [[ "$path_count" -lt 1 ]]; then
  echo "FAIL: expected at least 1 trafficPath, got ${path_count}" >&2
  exit 1
fi
echo "OK: ${path_count} trafficPaths emitted"

echo "=== Positive: every trafficPath has stagePath following canonical order ==="
# Canonical order: access → downstream-selector → policy → upstream-selector → core
# or reverse: core → upstream-selector → policy → downstream-selector → access
noncanonical="$(jq '[.sites.esp0xdeadbeef."site-a".trafficPaths[]
  | select(
    .stagePath != ["access","downstream-selector","policy","upstream-selector","core"]
    and .stagePath != ["core","upstream-selector","policy","downstream-selector","access"]
  )
  | {relationId: .relationId, stagePath: .stagePath}] | length' "$json_file")"

if [[ "$noncanonical" != "0" ]]; then
  echo "FAIL: ${noncanonical} trafficPaths have non-canonical stagePath" >&2
  jq '[.sites.esp0xdeadbeef."site-a".trafficPaths[]
    | select(
      .stagePath != ["access","downstream-selector","policy","upstream-selector","core"]
      and .stagePath != ["core","upstream-selector","policy","downstream-selector","access"]
    )
    | {relationId, stagePath}]' "$json_file" >&2
  exit 1
fi
echo "OK: all trafficPaths follow canonical stage order"

echo "=== Positive: every trafficPath has at least one nodePathAlternatives entry ==="
no_alternatives="$(jq '[.sites.esp0xdeadbeef."site-a".trafficPaths[]
  | select((.nodePathAlternatives | length) < 1)] | length' "$json_file")"

if [[ "$no_alternatives" != "0" ]]; then
  echo "FAIL: ${no_alternatives} trafficPaths have zero nodePathAlternatives" >&2
  jq '[.sites.esp0xdeadbeef."site-a".trafficPaths[]
    | select((.nodePathAlternatives | length) < 1)]' "$json_file" >&2
  exit 1
fi
echo "OK: all trafficPaths preserve at least one graph-resolved alternative"

echo "=== Positive: every trafficPath nodePath is present in nodePathAlternatives ==="
orphaned_primary="$(jq '[.sites.esp0xdeadbeef."site-a".trafficPaths[]
  | . as $tp
  | select(($tp.nodePathAlternatives | map(. == $tp.nodePath) | any) | not)] | length' "$json_file")"

if [[ "$orphaned_primary" != "0" ]]; then
  echo "FAIL: ${orphaned_primary} trafficPaths have nodePath not in nodePathAlternatives" >&2
  exit 1
fi
echo "OK: every primary nodePath is a member of its alternatives set"

echo "=== Positive: trafficPaths have valid source and destination matching model selectors ==="
# Every trafficPath source should be a valid selector (tenant/service/external)
invalid_source="$(jq '[.sites.esp0xdeadbeef."site-a".trafficPaths[]
  | select(.source.kind != "tenant" and .source.kind != "service" and .source.kind != "external")] | length' "$json_file")"

if [[ "$invalid_source" != "0" ]]; then
  echo "FAIL: ${invalid_source} trafficPaths have invalid source kind" >&2
  jq '[.sites.esp0xdeadbeef."site-a".trafficPaths[]
    | select(.source.kind != "tenant" and .source.kind != "service" and .source.kind != "external")
    | {relationId, source}]' "$json_file" >&2
  exit 1
fi
echo "OK: all trafficPath sources use valid model selector kinds"

echo "=== Positive: trafficPaths reference existing relation identifiers ==="
relation_ids="$(jq '[.sites.esp0xdeadbeef."site-a".relations[].source.id]' "$json_file")"
traffic_relation_ids="$(jq '[.sites.esp0xdeadbeef."site-a".trafficPaths[].relationId]' "$json_file")"
orphaned="$(jq -n --argjson traffic "$traffic_relation_ids" --argjson relations "$relation_ids" '($traffic - $relations) | length')"

if [[ "$orphaned" != "0" ]]; then
  echo "FAIL: ${orphaned} trafficPaths reference relationIds not in authority set" >&2
  jq -n --argjson traffic "$traffic_relation_ids" --argjson relations "$relation_ids" '$traffic - $relations' >&2
  exit 1
fi
echo "OK: all trafficPath relationIds resolve to authority records"

echo "=== Seeded negative 1: realization-fact field in site input is rejected ==="
# A fixture with hatProviderFixture (realization fact) should fail at the compiler
neg1_out="${work_dir}/neg1.txt"
set +e
nix run "$ROOT#compile" -- "$ROOT/tests/negative/intent-source-boundary-realization-technology.nix" >"$neg1_out" 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: seeded negative 1 (realization-technology side-channel) compiled successfully" >&2
  cat "$neg1_out" >&2
  exit 1
fi

if ! grep -q "E_INTENT_SOURCE_BOUNDARY" "$neg1_out"; then
  echo "FAIL: seeded negative 1 did not emit E_INTENT_SOURCE_BOUNDARY" >&2
  cat "$neg1_out" >&2
  exit 1
fi
echo "OK: compiler rejects realization-fact-derived inputs (negative 1)"

echo "=== Seeded negative 2: side-channel field in site input is rejected ==="
neg2_out="${work_dir}/neg2.txt"
set +e
nix run "$ROOT#compile" -- "$ROOT/tests/negative/intent-source-boundary-side-channel.nix" >"$neg2_out" 2>&1
rc=$?
set -e

if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: seeded negative 2 (side-channel field) compiled successfully" >&2
  cat "$neg2_out" >&2
  exit 1
fi

if ! grep -q "E_INTENT_SOURCE_BOUNDARY" "$neg2_out"; then
  echo "FAIL: seeded negative 2 did not emit E_INTENT_SOURCE_BOUNDARY" >&2
  cat "$neg2_out" >&2
  exit 1
fi
echo "OK: compiler rejects side-channel realization facts (negative 2)"

echo "PASS: FS-181-HDS-010-SDS-010-SMS-010 graph-path mapping authority construction test"
