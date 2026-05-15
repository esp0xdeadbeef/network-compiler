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

service_access_input="${tmp_dir}/service-access.nix"
cat > "$service_access_input" <<'EOF'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };

      ownership = {
        prefixes = [
          { kind = "tenant"; name = "client"; ipv4 = "10.20.20.0/24"; }
          { kind = "tenant"; name = "dmz"; ipv4 = "10.20.30.0/24"; }
        ];
        endpoints = [
          { kind = "host"; name = "dns-dmz"; tenant = "dmz"; }
        ];
      };

      communicationContract = {
        trafficTypes = [ ];
        services = [
          { name = "dns-dmz"; providers = [ "dns-dmz" ]; trafficType = "any"; }
        ];
        relations = [
          {
            id = "allow-client-to-dmz-dns";
            priority = 100;
            from = { kind = "tenant-set"; members = [ "client" ]; };
            to = { kind = "service"; name = "dns-dmz"; };
            trafficType = "any";
            action = "allow";
          }
          {
            id = "allow-dmz-dns-to-uplink0";
            priority = 110;
            from = { kind = "service"; name = "dns-dmz"; };
            to = { kind = "external"; uplinks = [ "uplink0" ]; };
            trafficType = "any";
            action = "allow";
          }
          {
            id = "allow-uplink0-to-dmz-dns";
            priority = 120;
            from = { kind = "external"; uplinks = [ "uplink0" ]; };
            to = { kind = "service"; name = "dns-dmz"; };
            trafficType = "any";
            action = "allow";
          }
          {
            id = "allow-client-to-uplink0";
            priority = 130;
            from = { kind = "tenant-set"; members = [ "client" ]; };
            to = { kind = "external"; uplinks = [ "uplink0" ]; };
            trafficType = "any";
            action = "allow";
          }
        ];
      };

      topology.nodes = {
        s-router-access-client = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
        };
        s-router-access-dmz = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "dmz"; } ];
        };
        s-router-downstream-selector.role = "downstream-selector";
        s-router-policy.role = "policy";
        s-router-upstream-selector.role = "upstream-selector";
        s-router-core = {
          role = "core";
          uplinks.uplink0.ipv4 = [ "0.0.0.0/0" ];
        };
      };

      topology.links = [
        [ "s-router-access-client" "s-router-downstream-selector" ]
        [ "s-router-access-dmz" "s-router-downstream-selector" ]
        [ "s-router-downstream-selector" "s-router-policy" ]
        [ "s-router-policy" "s-router-upstream-selector" ]
        [ "s-router-upstream-selector" "s-router-core" ]
      ];
    };
  };
}
EOF

service_access_json="${tmp_dir}/service-access.json"
nix run "$ROOT#compile" -- "$service_access_input" > "$service_access_json"

jq -e '
  ([
    .sites.esp0xdeadbeef."site-a".trafficPaths[]
    | select(.relationId == "allow-client-to-dmz-dns")
    | select(.nodePath == [
        "s-router-access-client",
        "s-router-downstream-selector",
        "s-router-policy",
        "s-router-downstream-selector",
        "s-router-access-dmz"
      ])
  ] | length == 1)
  and
  ([
    .sites.esp0xdeadbeef."site-a".trafficPaths[]
    | select(.relationId == "allow-dmz-dns-to-uplink0")
    | select(.nodePath[0] == "s-router-access-dmz")
  ] | length == 1)
  and
  ([
    .sites.esp0xdeadbeef."site-a".trafficPaths[]
    | select(.relationId == "allow-uplink0-to-dmz-dns")
    | select(.nodePath[-1] == "s-router-access-dmz")
  ] | length == 1)
' "$service_access_json" >/dev/null

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
