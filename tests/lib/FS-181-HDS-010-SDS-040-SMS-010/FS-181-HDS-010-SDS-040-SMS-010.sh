#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-181-HDS-010-SDS-040-SMS-010
# GAMP-SCOPE: control-module-construction
# CMC construction test: Rendered authority set conformance
# Proves every relation emitted by the compiler carries a traceable
# authority identifier, and the authority set is self-consistent.
#
# SMS Acceptance Predicates:
#   P1 ✓ Every relation has authority identifier (source.id)
#   P2 ✓ Authority identifiers are unique (no duplicates)
#   P3 ✓ trafficPaths reference valid authority identifiers
#   P4 ✓ source.sourceAudit present with correct authority + sourceClass
#   N1 ✓ Missing sourceAudit → E_COMPILER_BEHAVIOR_SOURCE_AUDIT rejection
#   N2 ✓ Duplicate authority identifier → REJECT (NEW)
#   N3 ✓ trafficPath references non-existent relationId → REJECT (NEW)

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
TMPDIR="${TMPDIR:-/tmp}"
work_dir="$(mktemp -d "${TMPDIR%/}/fs181-auth-set.XXXXXX")"
trap 'rm -rf "$work_dir"' EXIT

failures=0

# ── Positive: single-wan fixture ──
json_file="${work_dir}/single-wan.json"
nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/single-uplink.nix" >"$json_file"

# P1: Every relation has a non-empty authority identifier
echo "=== P1: every relation has authority identifier (source.id) ==="
relation_count="$(jq '[.sites.esp0xdeadbeef."site-a".relations[] | select(.source.id != null and .source.id != "")] | length' "$json_file")"
total_relations="$(jq '.sites.esp0xdeadbeef."site-a".relations | length' "$json_file")"
if [[ "$relation_count" != "$total_relations" ]]; then
  echo "FAIL: ${total_relations} relations but only ${relation_count} have source.id" >&2
  jq '[.sites.esp0xdeadbeef."site-a".relations[] | select(.source.id == null or .source.id == "")]' "$json_file" >&2
  ((failures++))
else
  echo "OK: all ${total_relations} relations carry authority identifiers"
fi

# P2: Authority identifiers are unique (strengthened — verifies across entire set)
echo "=== P2: authority identifiers are unique — no duplicate source.id ==="
dup_count="$(jq '[.sites.esp0xdeadbeef."site-a".relations | group_by(.source.id)[] | select(length > 1)] | length' "$json_file")"
if [[ "$dup_count" != "0" ]]; then
  echo "FAIL: ${dup_count} duplicate authority identifier groups found" >&2
  jq '.sites.esp0xdeadbeef."site-a".relations | group_by(.source.id) | map(select(length > 1))' "$json_file" >&2
  ((failures++))
else
  echo "OK: all ${total_relations} authority identifiers are unique"
fi

# P3: trafficPaths reference valid authority identifiers
echo "=== P3: trafficPaths reference valid authority identifiers ==="
traffic_relation_ids="$(jq '[.sites.esp0xdeadbeef."site-a".trafficPaths[].relationId] | unique' "$json_file")"
relation_source_ids="$(jq '[.sites.esp0xdeadbeef."site-a".relations[].source.id] | unique' "$json_file")"
orphaned_traffic="$(jq -n --argjson traffic "$traffic_relation_ids" --argjson relations "$relation_source_ids" '$traffic - $relations | length')"
if [[ "$orphaned_traffic" != "0" ]]; then
  echo "FAIL: ${orphaned_traffic} trafficPaths reference non-existent relation IDs" >&2
  jq -n --argjson traffic "$traffic_relation_ids" --argjson relations "$relation_source_ids" '$traffic - $relations' >&2
  ((failures++))
else
  echo "OK: all trafficPath relationIds resolve to authority identifiers"
fi

# P4: Every relation has source.sourceAudit with correct authority + sourceClass
echo "=== P4: every relation has source.sourceAudit (authority + sourceClass) ==="
audited_count="$(jq '[.sites.esp0xdeadbeef."site-a".relations[] | select(.source.sourceAudit.authority == "network-compiler" and .source.sourceAudit.sourceClass == "user-intent")] | length' "$json_file")"
if [[ "$audited_count" != "$total_relations" ]]; then
  echo "FAIL: ${total_relations} relations but only ${audited_count} have complete network-compiler/user-intent audit" >&2
  jq '[.sites.esp0xdeadbeef."site-a".relations[] | select(.source.sourceAudit.authority != "network-compiler" or .source.sourceAudit.sourceClass != "user-intent")]' "$json_file" >&2
  ((failures++))
else
  echo "OK: all ${total_relations} relations traced to network-compiler authority, user-intent sourced"
fi

# ── NEW: Multi-uplink fixture — verify uniqueness across larger authority set ──
echo "=== P2+ (multi-uplink): uniqueness across larger authority set ==="
multi_json="${work_dir}/multi-uplink.json"
nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/multi-uplink.nix" >"$multi_json"

# Get all relation source.ids across both sites
all_ids="$(jq '[.sites.esp0xdeadbeef."site-a".relations[].source.id, .sites.esp0xdeadbeef."site-b".relations[].source.id]' "$multi_json")"
all_dup_count="$(echo "$all_ids" | jq 'group_by(.) | map(select(length > 1)) | length')"
if [[ "$all_dup_count" != "0" ]]; then
  echo "FAIL: ${all_dup_count} duplicate authority identifiers across sites" >&2
  echo "$all_ids" | jq 'group_by(.) | map(select(length > 1))' >&2
  ((failures++))
else
  echo "OK: all authority identifiers unique across multi-site fixture"
fi

# ── Seeded negative 1: missing sourceAudit → REJECT ──
echo "=== N1: missing sourceAudit → E_COMPILER_BEHAVIOR_SOURCE_AUDIT rejection ==="
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
  echo "FAIL: seeded negative 1 (missing sourceAudit) was not rejected" >&2
  ((failures++))
elif ! grep -q "E_COMPILER_BEHAVIOR_SOURCE_AUDIT" "${work_dir}/neg1.txt"; then
  echo "FAIL: seeded negative 1 did not produce E_COMPILER_BEHAVIOR_SOURCE_AUDIT" >&2
  cat "${work_dir}/neg1.txt" >&2
  ((failures++))
else
  echo "OK: module correctly rejects relation without sourceAudit (N1)"
fi

# ── NEW Seeded negative 2: duplicate authority identifier → REJECT ──
echo "=== N2: duplicate authority identifier → REJECT ==="
dup_expr='
let
  flake = builtins.getFlake "path:'"$ROOT"'";
  lib = flake.inputs.nixpkgs.lib;
  audit = import "'"$ROOT"'/lib/stages/source-audit.nix" { inherit lib; };
  model = {
    tenants = [ { name = "mgmt"; } { name = "adm"; } ];
    services = [ ];
    isolationDecisions = [ ];
    ipv6 = { };
    relations = [
      {
        id = "dup-allow-mgmt-to-wan";
        priority = 100;
        from = { kind = "tenant"; name = "mgmt"; };
        to = { kind = "external"; uplinks = [ "wan" ]; };
        trafficType = "any";
        action = "allow";
        source = {
          id = "DUPLICATE-AUTHORITY-ID";
          kind = "relation";
          priority = 100;
          sourceAudit = {
            authority = "network-compiler";
            sourceClass = "user-intent";
          };
        };
      }
      {
        id = "dup-allow-adm-to-wan";
        priority = 200;
        from = { kind = "tenant"; name = "adm"; };
        to = { kind = "external"; uplinks = [ "wan" ]; };
        trafficType = "any";
        action = "allow";
        source = {
          id = "DUPLICATE-AUTHORITY-ID";  # SAME ID as above — this is the duplicate
          kind = "relation";
          priority = 200;
          sourceAudit = {
            authority = "network-compiler";
            sourceClass = "user-intent";
          };
        };
      }
    ];
    trafficPaths = [ ];
    overlayAttachments = { };
    overlayAddressPools = { };
    hostNatIngress = { };
  };
in
  audit.validate "dup-test" model
'

set +e
nix eval --impure --expr "$dup_expr" >"${work_dir}/neg2.txt" 2>&1
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: seeded negative 2 (duplicate authority ID) was not rejected" >&2
  ((failures++))
elif ! grep -qE "E_COMPILER|duplicate|DUPLICATE" "${work_dir}/neg2.txt"; then
  echo "FAIL: seeded negative 2 did not produce expected rejection diagnostic" >&2
  cat "${work_dir}/neg2.txt" >&2
  ((failures++))
else
  echo "OK: module correctly rejects duplicate authority identifier (N2)"
fi

# ── NEW Seeded negative 3: trafficPath references non-existent relationId ──
echo "=== N3: trafficPath with missing relationId in authority set → REJECT ==="
orphan_expr='
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
        id = "allow-mgmt-to-wan";
        priority = 100;
        from = { kind = "tenant"; name = "mgmt"; };
        to = { kind = "external"; uplinks = [ "wan" ]; };
        trafficType = "any";
        action = "allow";
        source = {
          id = "allow-mgmt-to-wan";
          kind = "relation";
          priority = 100;
          sourceAudit = {
            authority = "network-compiler";
            sourceClass = "user-intent";
          };
        };
      }
    ];
    trafficPaths = [
      {
        relationId = "NONEXISTENT-RELATION-ID";  # does NOT exist in relations[]
        source = { kind = "tenant"; name = "mgmt"; };
        destination = { kind = "external"; uplinks = [ "wan" ]; };
        stagePath = [ "access" "downstream-selector" "policy" "upstream-selector" "core" ];
        nodePath = [ ];
        nodePathAlternatives = [ [ ] ];
        direction = "egress";
      }
    ];
    overlayAttachments = { };
    overlayAddressPools = { };
    hostNatIngress = { };
  };
in
  audit.validate "orphan-test" model
'

set +e
nix eval --impure --expr "$orphan_expr" >"${work_dir}/neg3.txt" 2>&1
rc=$?
set -e
if [[ "$rc" -eq 0 ]]; then
  echo "FAIL: seeded negative 3 (orphan trafficPath relationId) was not rejected" >&2
  ((failures++))
elif ! grep -qE "E_COMPILER|orphan|NONEXISTENT|unresolved|missing" "${work_dir}/neg3.txt"; then
  echo "FAIL: seeded negative 3 did not produce expected rejection diagnostic" >&2
  cat "${work_dir}/neg3.txt" >&2
  ((failures++))
else
  echo "OK: module correctly rejects trafficPath with non-existent relationId (N3)"
fi

# ── Final result ──
if [[ "$failures" -eq 0 ]]; then
  echo "PASS: FS-181-HDS-010-SDS-040-SMS-010 authority-set conformance construction test"
else
  echo "FAIL: ${failures} check(s) failed" >&2
  exit 1
fi
