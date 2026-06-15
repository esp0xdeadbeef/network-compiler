#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-290-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

good_input="${tmp_dir}/fs290-access-space-discovery-good.nix"
good_output="${tmp_dir}/fs290-access-space-discovery-good.json"

cat >"$good_input" <<'NIX'
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
          { kind = "tenant"; name = "streaming"; ipv4 = "10.20.50.0/24"; }
          { kind = "tenant"; name = "guest"; ipv4 = "10.20.60.0/24"; }
        ];
        endpoints = [
          { kind = "host"; name = "receiver01"; tenant = "streaming"; }
        ];
      };

      profileManifest = {
        accessSpaces = {
          client.localServiceDiscovery = "cast-requester";
          streaming.localServiceDiscovery = "cast-responder";
          guest.localServiceDiscovery = "disabled";
        };
        tenantAccessMatrix = [
          {
            scope = "client";
            discoveryExports = [ "cast-discovery" ];
            allowedServices = [ "cast-control" ];
          }
          {
            scope = "streaming";
            discoveryExports = [ ];
            allowedServices = [ ];
          }
          {
            scope = "guest";
            discoveryExports = [ ];
            allowedServices = [ ];
          }
        ];
        sharedServiceMatrix = [
          {
            requesterScopes = [ "client" ];
            responderScope = "streaming";
            serviceClass = "media-receiver";
            service = "cast-discovery";
            discovery = {
              protocol = "mdns-ssdp";
              direction = "client-to-streaming";
            };
            payload = {
              protocol = "udp";
              ports = [ 5353 1900 ];
              direction = "requester-to-responder";
              returnBehavior = "discovery-response-only";
            };
          }
          {
            requesterScopes = [ "client" ];
            responderScope = "streaming";
            serviceClass = "media-control";
            service = "cast-control";
            discovery = {
              protocol = "none";
              direction = "not-discovered";
            };
            payload = {
              protocol = "tcp";
              ports = [ 8008 8009 ];
              direction = "client-to-streaming";
              returnBehavior = "stateful-return";
            };
          }
        ];
      };

      communicationContract = {
        trafficTypes = [
          { name = "cast-discovery"; match = [ { proto = "udp"; family = "any"; dports = [ 5353 1900 ]; } ]; }
          { name = "cast-control"; match = [ { proto = "tcp"; family = "any"; dports = [ 8008 8009 ]; } ]; }
        ];
        services = [
          {
            name = "cast-discovery";
            providers = [ "receiver01" ];
            trafficType = "cast-discovery";
          }
          {
            name = "cast-control";
            providers = [ "receiver01" ];
            trafficType = "cast-control";
          }
        ];
        relations = [
          {
            id = "allow-client-to-cast-control";
            priority = 100;
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "service"; name = "cast-control"; };
            trafficType = "cast-control";
            action = "allow";
          }
          {
            id = "allow-client-to-wan";
            priority = 110;
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "external"; uplinks = [ "wan" ]; };
            trafficType = "cast-control";
            action = "allow";
          }
        ];
      };

      topology.nodes = {
        access-client = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
        };
        access-streaming = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "streaming"; } ];
        };
        access-guest = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "guest"; } ];
        };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
      };

      topology.links = [
        [ "access-client" "downstream" ]
        [ "access-streaming" "downstream" ]
        [ "access-guest" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
NIX

nix run "$ROOT#compile" -- "$good_input" >"$good_output"

jq -e '
  .sites.esp0xdeadbeef."site-a".accessSpaceDiscovery as $discovery
  | ($discovery.confined | length == 3)
  and (
    $discovery.confined[]
    | select(.scope == "client")
    | .confinedByDefault == true
      and .discoveryExports == ["cast-discovery"]
      and (.deniedCrossScopeByDefault | length == 0)
  )
  and (
    $discovery.confined[]
    | select(.scope == "guest")
    | .confinedByDefault == true
      and .discoveryExports == []
      and (.deniedCrossScopeByDefault | length == 0)
  )
  and ($discovery.exported | length == 1)
  and (
    $discovery.exported[0]
    | .requesterScope == "client"
      and .responderScope == "streaming"
      and .service == "cast-discovery"
      and .serviceType == "media-receiver"
      and .discovery == { protocol: "mdns-ssdp", direction: "client-to-streaming" }
      and .relayOrProxyBoundary == "access-space-local-service-discovery:cast-requester->cast-responder"
      and .payload == {
        authorized: false,
        inferredFromDiscovery: false,
        protocol: "udp",
        ports: [5353, 1900],
        direction: "requester-to-responder",
        returnBehavior: "discovery-response-only"
      }
  )
' "$good_output" >/dev/null

expect_failure() {
  local label="$1"
  local search="$2"
  local replace="$3"
  local expected_code="$4"
  local input="${tmp_dir}/${label}.nix"
  local err="${tmp_dir}/${label}.err"

  sed "s/${search}/${replace}/" "$good_input" >"$input"

  set +e
  nix run "$ROOT#compile" -- "$input" 2>"$err" >/dev/null
  local rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL fs290 access-space discovery: ${label} compiled" >&2
    exit 1
  fi
  grep -q "$expected_code" "$err"
}

expect_failure \
  "missing-export" \
  "discoveryExports = \\[ \"cast-discovery\" \\];" \
  "discoveryExports = [ ];" \
  "E_ACCESS_SPACE_DISCOVERY_CROSS_SCOPE_DENIED"

expect_failure \
  "unknown-export-service" \
  "discoveryExports = \\[ \"cast-discovery\" \\];" \
  "discoveryExports = [ \"rogue-discovery\" ];" \
  "E_ACCESS_SPACE_DISCOVERY_EXPORT_UNKNOWN_SERVICE"

expect_failure \
  "payload-inferred-from-discovery" \
  "protocol = \"mdns-ssdp\";" \
  "protocol = \"mdns-ssdp\"; grantsPayloadReachability = true;" \
  "E_ACCESS_SPACE_DISCOVERY_PAYLOAD_INFERENCE"

echo "PASS FS-290-HDS-010-SDS-010-SMS-020"