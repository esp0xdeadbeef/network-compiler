#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

positive_cases=(
  single-wan
  multi-wan
  multi-enterprise
  priority-stability
  overlay-east-west
)

negative_nix_cases=(
  "$ROOT/tests/negative/disconnected.nix"
  "$ROOT/tests/negative/allocator-exhaustion.nix"
  "$ROOT/tests/negative/exposed-service-without-ingress.nix"
  "$ROOT/tests/negative/core-missing-upstreams.nix"
  "$ROOT/tests/negative/multi-wan-missing-upstream-selector.nix"
  "$ROOT/tests/negative/overlay-without-core.nix"
  "$ROOT/tests/negative/overlay-on-non-core.nix"
  "$ROOT/tests/negative/overlay-defined-without-policy-rules.nix"
)

echo "=== negative tests (inputs.nix fixtures) ==="
for file in "${negative_nix_cases[@]}"; do
  echo "checking (expect failure): $file"

  set +e
  nix run "$ROOT#compile" -- "$file" 2>&1 | tee /dev/stderr
  rc=${PIPESTATUS[0]}
  set -e

  if [ "$rc" -eq 0 ]; then
    echo "❌ expected failure but succeeded: $file"
    exit 1
  fi

  echo "✔ failure detected"
done

echo "=== positive tests ==="
for name in "${positive_cases[@]}"; do
  echo "checking: $name"
  nix run "$ROOT#compile" -- "$ROOT/examples/$name/inputs.nix" \
    | jq -S 'del(.meta)' \
    > /dev/null
done

echo "=== regression tests ==="
single_wan_json="$(mktemp)"
trap 'rm -f "$single_wan_json"' EXIT

nix run "$ROOT#compile" -- "$ROOT/examples/single-wan/inputs.nix" > "$single_wan_json"

jq -e '
  [
    .sites.esp0xdeadbeef."site-a".communicationContract.allowedRelations[]
    | select(.source.id == "allow-wan-to-jump-host")
    | select(.from == { kind: "external", name: "wan" })
    | select(.to == { kind: "service", name: "jump-host" })
  ] | length == 1
' "$single_wan_json" > /dev/null

jq -e '
  [
    .sites.esp0xdeadbeef."site-a".communicationContract.allowedRelations[]
    | select(.source.id == "allow-wan-to-admin-web")
    | select(.from == { kind: "external", name: "wan" })
    | select(.to == { kind: "service", name: "admin-web" })
  ] | length == 1
' "$single_wan_json" > /dev/null

jq -e '
  [
    .sites.esp0xdeadbeef."site-a".communicationContract.allowedRelations[]
    | select(.source.id == "allow-wan-to-mgmt-icmp")
    | select(.from == { kind: "external", name: "wan" })
    | select(.to == { kind: "tenant", name: "mgmt" })
  ] | length == 1
' "$single_wan_json" > /dev/null

jq -e '
  [
    .sites.esp0xdeadbeef."site-a".communicationContract.allowedRelations[]
    | select(.from == { kind: "tenant-set", members: [] })
  ] | length == 0
' "$single_wan_json" > /dev/null

echo "all tests passed"
