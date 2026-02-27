# ./tests/check.sh
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

positive_cases=(
  single-wan
  multi-wan
  multi-enterprise
  priority-stability
)

echo "=== negative tests (jq-mutated output) ==="

BASE_OUTPUT="$(mktemp)"

# Capture clean JSON only
nix run "$ROOT#compile" -- "$ROOT/examples/single-wan/inputs.nix" 2>/dev/null \
  | jq -S 'del(.meta)' > "$BASE_OUTPUT"

# Validate base JSON explicitly
jq empty "$BASE_OUTPUT"

make_invalid() {
  local filter="$1"
  local out="$2"
  jq "$filter" "$BASE_OUTPUT" > "$out"
  jq empty "$out"
}

# 1. Remove NAT from core in canonical model
make_invalid '
  .sites |= with_entries(
    .value |= with_entries(
      .value |= (
        .routerLoopbacks["s-router-core"] = null
      )
    )
  )
' /tmp/invalid-no-custom-core.json

# 2. Remove ingress
make_invalid '
  .sites |= with_entries(
    .value |= with_entries(
      .value |= (
        .communicationContract.nat.ingress = []
      )
    )
  )
' /tmp/invalid-no-ingress.json

# 3. Duplicate rule priority
make_invalid '
  .sites |= with_entries(
    .value |= with_entries(
      .value |= (
        .communicationContract.allowedRelations[0].source.priority = 100
        | .communicationContract.allowedRelations[1].source.priority = 100
      )
    )
  )
' /tmp/invalid-duplicate-priority.json

# 4. Break address pool
make_invalid '
  .sites |= with_entries(
    .value |= with_entries(
      .value |= (
        .addressPools.local.ipv4 = "10.19.0.0/32"
      )
    )
  )
' /tmp/invalid-allocator.json

invalid_cases=(
  /tmp/invalid-no-custom-core.json
  /tmp/invalid-no-ingress.json
  /tmp/invalid-duplicate-priority.json
  /tmp/invalid-allocator.json
)

for file in "${invalid_cases[@]}"; do
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

rm -f "$BASE_OUTPUT" /tmp/invalid-*.json

echo "=== positive tests ==="
for name in "${positive_cases[@]}"; do
  echo "checking: $name"

  nix run "$ROOT#compile" -- "$ROOT/examples/$name/inputs.nix" \
    | jq -S 'del(.meta)' \
    > /dev/null
done

echo "all tests passed"
