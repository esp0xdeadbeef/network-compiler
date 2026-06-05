#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-590-HDS-010-SDS-010-SMS-020
# GAMP-ID: FS-590-HDS-010-SDS-010-SMS-030
# GAMP-ID: FS-590-HDS-010-SDS-010-SMS-040
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

good_input="${tmp_dir}/fs590-discovery-policy-good.nix"
good_output="${tmp_dir}/fs590-discovery-policy-good.json"

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
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "client"; } ];
              responderScope = { kind = "host"; name = "receiver01"; tenant = "streaming"; };
              serviceClass = "media-receiver";
              discovery = {
                protocol = "mdns";
                direction = "responder-to-controller";
                advertisedServices = [ "_googlecast._tcp" "_airplay._tcp" ];
              };
              payload = {
                protocol = "tcp";
                ports = [ 8008 8009 ];
                direction = "controller-to-receiver";
                returnBehavior = "established-only";
              };
              management = {
                allowed = false;
                boundary = "receiver-management-denied";
              };
              reverseInitiation = {
                allowed = false;
                boundary = "no-receiver-initiated-client-paths";
              };
              deniedPaths = [
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "cast-discovery"; }; reason = "guest-discovery-denied"; negativeProbe = "guest-to-cast-mdns"; }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "receiver-pairing";
              cloudDependency = "optional";
            };
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
  .sites.esp0xdeadbeef."site-a" as $site
  | $site.accessSpaceDiscovery as $discovery
  | ($discovery.confined | length == 3)
  and (
    $discovery.confined[]
    | select(.scope == "client")
    | .confinedByDefault == true
      and .discoveryExports == ["cast-discovery"]
      and (.deniedCrossScopeByDefault | length == 0)
  )
  and (
    $discovery.exported | length == 1
  )
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
  and (
    $site.services[]
    | select(.name == "cast-discovery")
    | .serviceClass == "media-receiver"
      and .discovery == {
        protocol: "mdns",
        direction: "responder-to-controller",
        advertisedServices: ["_googlecast._tcp", "_airplay._tcp"]
      }
      and .payload == {
        protocol: "tcp",
        ports: [8008, 8009],
        direction: "controller-to-receiver",
        returnBehavior: "established-only"
      }
      and .management == { allowed: false, boundary: "receiver-management-denied" }
      and .reverseInitiation == { allowed: false, boundary: "no-receiver-initiated-client-paths" }
      and .authenticationBoundary == "receiver-pairing"
      and .cloudDependency == "optional"
  )
' "$good_output" >/dev/null

expect_failure() {
  local label="$1"
  local search="$2"
  local replace="$3"
  local expected_code="$4"
  local expected_text="$5"
  local input="${tmp_dir}/${label}.nix"
  local err="${tmp_dir}/${label}.err"

  sed "s/${search}/${replace}/" "$good_input" >"$input"

  set +e
  nix run "$ROOT#compile" -- "$input" 2>"$err" >/dev/null
  local rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL fs590 discovery policy: ${label} compiled" >&2
    exit 1
  fi

  grep -q "$expected_code" "$err"
  grep -q "$expected_text" "$err"
}

expect_failure \
  "cross-boundary-without-export" \
  "discoveryExports = \\[ \"cast-discovery\" \\];" \
  "discoveryExports = [ ];" \
  "E_ACCESS_SPACE_DISCOVERY_CROSS_SCOPE_DENIED" \
  "cross-scope discovery for service 'cast-discovery' from 'client' to 'streaming' is denied without discoveryExports authority"

expect_failure \
  "missing-transport-protocol" \
  "protocol = \"mdns-ssdp\";" \
  "# protocol omitted" \
  "E_ACCESS_SPACE_DISCOVERY_PROTOCOL" \
  "must declare discovery.protocol"

expect_failure \
  "missing-relay-boundary" \
  "client.localServiceDiscovery = \"cast-requester\";" \
  "client.localServiceDiscovery = \"\";" \
  "E_ACCESS_SPACE_DISCOVERY_BOUNDARY_REQUIRED" \
  "must declare localServiceDiscovery before exporting discovery"

expect_failure \
  "infer-discovery-from-service-existence" \
  "cloudDependency = \"optional\";" \
  "cloudDependency = \"optional\"; inferDiscoveryFromServiceExistence = true;" \
  "E_SERVICE_POLICY_INFERRED_AUTHORITY" \
  "must not infer authority from 'inferDiscoveryFromServiceExistence'"

expect_failure \
  "infer-payload-from-discovery" \
  "cloudDependency = \"optional\";" \
  "cloudDependency = \"optional\"; inferPayloadFromDiscovery = true;" \
  "E_SERVICE_POLICY_INFERRED_AUTHORITY" \
  "must not infer authority from 'inferPayloadFromDiscovery'"

echo "PASS fs590-discovery-policy-contract"
