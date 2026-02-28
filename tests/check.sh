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

echo "all tests passed"
