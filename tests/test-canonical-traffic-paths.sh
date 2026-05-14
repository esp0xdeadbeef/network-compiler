#!/usr/bin/env bash
set -euo pipefail

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

output_json="${tmp_dir}/single-uplink.json"
nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/single-uplink.nix" > "$output_json"

jq -e '
  [
    .sites.esp0xdeadbeef."site-a".trafficPaths[]
    | select(.relationId == "allow-mgmt-to-uplink0")
    | select(.stagePath == [
        "access",
        "downstream-selector",
        "policy",
        "upstream-selector",
        "core"
      ])
    | select(.nodePath == [
        "s-router-access",
        "s-router-downstream-selector",
        "s-router-policy",
        "s-router-upstream-selector",
        "s-router-core"
      ])
    | select(.requiresPolicy == true)
    | select(.forbidsCoreToCoreP2P == true)
    | select(.p2pIsolationKey == "allow-mgmt-to-uplink0")
  ] | length == 1
' "$output_json" >/dev/null

jq -e '
  [
    .sites.esp0xdeadbeef."site-a".trafficPaths[]
    | select(.relationId == "allow-uplink0-to-mgmt-icmp")
    | select(.stagePath == [
        "core",
        "upstream-selector",
        "policy",
        "downstream-selector",
        "access"
      ])
  ] | length == 1
' "$output_json" >/dev/null

multi_output_json="${tmp_dir}/multi-uplink.json"
nix run "$ROOT#compile" -- "$ROOT/tests/fixtures/multi-uplink.nix" > "$multi_output_json"

jq -e '
  [
    .sites.esp0xdeadbeef."site-a".trafficPaths[]
    | select(.relationId == "allow-tenants-to-explicit-uplinks")
    | select(.corePathNodes == [
        "s-router-core-isp-a",
        "s-router-core-isp-b"
      ])
    | select(.nodePathAlternatives == [
        [
          "s-router-access-adm",
          "s-router-downstream-selector",
          "s-router-policy",
          "s-router-upstream-selector",
          "s-router-core-isp-a"
        ],
        [
          "s-router-access-adm",
          "s-router-downstream-selector",
          "s-router-policy",
          "s-router-upstream-selector",
          "s-router-core-isp-b"
        ]
      ])
  ] | length == 1
' "$multi_output_json" >/dev/null

for bad in core-to-core-link policy-bypass-link; do
  set +e
  output="$(nix run "$ROOT#compile" -- "$ROOT/tests/negative/${bad}.nix" 2>&1)"
  rc=$?
  set -e

  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL ${bad}: expected canonical stage invariant failure" >&2
    exit 1
  fi

  if ! grep -q "E_TOPO_NON_CANONICAL_STAGE_LINK" <<<"$output"; then
    echo "FAIL ${bad}: missing E_TOPO_NON_CANONICAL_STAGE_LINK" >&2
    printf '%s\n' "$output" >&2
    exit 1
  fi
done

echo "PASS canonical-traffic-paths"
