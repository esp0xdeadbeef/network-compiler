#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"

signed_json_out="$(mktemp)"
trap 'rm -f "$signed_json_out"' EXIT
export OUTPUT_COMPILER_SIGNED_JSON="$signed_json_out"

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
"$ROOT/tests/negative/duplicate-uplink-name.nix"
"$ROOT/tests/negative/legacy-external-name-uplink.nix"
)

resolve_example() {
local name="$1"

case "$name" in
single-wan)
printf '%s\n' "$ROOT/tests/fixtures/single-uplink.nix"
;;
multi-wan)
printf '%s\n' "$ROOT/tests/fixtures/multi-uplink.nix"
;;
multi-enterprise)
printf '%s\n' "$ROOT/tests/fixtures/multi-enterprise.nix"
;;
priority-stability)
printf '%s\n' "$ROOT/tests/fixtures/priority-stability.nix"
;;
*)
echo "❌ unknown local fixture: $name" >&2
exit 1
;;
esac
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

single_wan_input="$ROOT/tests/fixtures/single-uplink.nix"
nix run "$ROOT#compile" -- "$single_wan_input" > "$single_wan_json"

jq -e '
[
.sites.esp0xdeadbeef."site-a".relations[]
| select(.source.id == "allow-uplink0-to-jump-host")
| select(.from == { kind: "external", uplinks: [ "uplink0" ] })
| select(.to == { kind: "service", name: "jump-host" })
] | length == 1
' "$single_wan_json" > /dev/null

jq -e '
[
.sites.esp0xdeadbeef."site-a".relations[]
| select(.source.id == "allow-uplink0-to-admin-web")
| select(.from == { kind: "external", uplinks: [ "uplink0" ] })
| select(.to == { kind: "service", name: "admin-web" })
] | length == 1
' "$single_wan_json" > /dev/null

jq -e '
[
.sites.esp0xdeadbeef."site-a".relations[]
| select(.source.id == "allow-uplink0-to-mgmt-icmp")
| select(.from == { kind: "external", uplinks: [ "uplink0" ] })
| select(.to == { kind: "tenant", name: "mgmt" })
] | length == 1
' "$single_wan_json" > /dev/null

jq -e '
[
.sites.esp0xdeadbeef."site-a".relations[]
| select(.from == { kind: "tenant-set", members: [] })
] | length == 0
' "$single_wan_json" > /dev/null

service_subject_input="$(mktemp)"
trap 'rm -f "$single_wan_json" "$service_subject_input"' EXIT

cat > "$service_subject_input" <<EOF
let
  base = import $ROOT/tests/fixtures/single-uplink.nix;
in
base
// {
  esp0xdeadbeef =
    base.esp0xdeadbeef
    // {
      "site-a" =
        base.esp0xdeadbeef."site-a"
        // {
          communicationContract =
            base.esp0xdeadbeef."site-a".communicationContract
            // {
              relations =
                base.esp0xdeadbeef."site-a".communicationContract.relations
                ++ [
                  {
                    id = "allow-jump-host-to-uplink0";
                    priority = 100;
                    from = {
                      kind = "service";
                      name = "jump-host";
                    };
                    to = {
                      kind = "external";
                      uplinks = [ "uplink0" ];
                    };
                    trafficType = "any";
                    action = "allow";
                  }
                ];
            };
        };
    };
}
EOF

service_subject_json="$(mktemp)"
trap 'rm -f "$single_wan_json" "$service_subject_input" "$service_subject_json"' EXIT
nix run "$ROOT#compile" -- "$service_subject_input" > "$service_subject_json"

jq -e '
[
.sites.esp0xdeadbeef."site-a".relations[]
| select(.source.id == "allow-jump-host-to-uplink0")
| select(.from == { kind: "service", name: "jump-host" })
| select(.to == { kind: "external", uplinks: [ "uplink0" ] })
] | length == 1
' "$service_subject_json" > /dev/null

"$ROOT/tests/test-dual-wan-branch-overlay.sh"

echo "all tests passed"
