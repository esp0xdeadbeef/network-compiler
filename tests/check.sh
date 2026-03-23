#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
EXAMPLE_REPO="$(nix flake prefetch github:esp0xdeadbeef/network-labs --json | jq -r .storePath)"
export NETWORK_LABS_REPO="$EXAMPLE_REPO"

positive_cases=(
single-wan
multi-wan
multi-enterprise
priority-stability
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

resolve_example() {
local name="$1"
local -a matches=()

while IFS= read -r -d '' path; do
matches+=("$path")
done < <(
find "$EXAMPLE_REPO" -type f \( -path "*/${name}/intent.nix" -o -path "*/${name}/inputs.nix" \) -print0 | sort -z
)

if [ "${#matches[@]}" -eq 0 ]; then
echo "❌ example not found in network-labs repo: $name" >&2
exit 1
fi

printf '%s\n' "${matches[0]}"
}

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
input_file="$(resolve_example "$name")"
nix run "$ROOT#compile" -- "$input_file" \
| jq -S 'del(.meta)' \
> /dev/null
done

echo "=== golden fixtures ==="
nix eval --impure --expr '
let
goldens = import '"$ROOT"'/tests/golden/default.nix { };
in
builtins.deepSeq goldens true
' > /dev/null

echo "=== regression tests ==="
single_wan_json="$(mktemp)"
trap 'rm -f "$single_wan_json"' EXIT

single_wan_input="$(resolve_example single-wan)"
nix run "$ROOT#compile" -- "$single_wan_input" > "$single_wan_json"

jq -e '
[
.sites.esp0xdeadbeef."site-a".relations[]
| select(.source.id == "allow-wan-to-jump-host")
| select(.from == { kind: "external", name: "wan" })
| select(.to == { kind: "service", name: "jump-host" })
] | length == 1
' "$single_wan_json" > /dev/null

jq -e '
[
.sites.esp0xdeadbeef."site-a".relations[]
| select(.source.id == "allow-wan-to-admin-web")
| select(.from == { kind: "external", name: "wan" })
| select(.to == { kind: "service", name: "admin-web" })
] | length == 1
' "$single_wan_json" > /dev/null

jq -e '
[
.sites.esp0xdeadbeef."site-a".relations[]
| select(.source.id == "allow-wan-to-mgmt-icmp")
| select(.from == { kind: "external", name: "wan" })
| select(.to == { kind: "tenant", name: "mgmt" })
] | length == 1
' "$single_wan_json" > /dev/null

jq -e '
[
.sites.esp0xdeadbeef."site-a".relations[]
| select(.from == { kind: "tenant-set", members: [] })
] | length == 0
' "$single_wan_json" > /dev/null

echo "all tests passed"
