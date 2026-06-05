#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-600-HDS-010-SDS-010-SMS-010
# GAMP-ID: FS-600-HDS-010-SDS-010-SMS-020
# GAMP-ID: FS-600-HDS-010-SDS-010-SMS-030
# GAMP-ID: FS-600-HDS-010-SDS-010-SMS-040
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

good_input="${tmp_dir}/fs600-discovery-payload-good.nix"
good_output="${tmp_dir}/fs600-discovery-payload-good.json"

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
          { kind = "tenant"; name = "consumer"; ipv4 = "10.20.10.0/24"; }
          { kind = "tenant"; name = "streaming"; ipv4 = "10.20.20.0/24"; }
        ];
        endpoints = [
          { kind = "host"; name = "tv01"; tenant = "streaming"; }
        ];
      };

      profileManifest = {
        accessSpaces = {
          consumer.localServiceDiscovery = "media-requester";
          streaming.localServiceDiscovery = "media-responder";
        };
        tenantAccessMatrix = [
          {
            scope = "consumer";
            discoveryExports = [ "smart-tv-browse" "smart-tv-probe" ];
            allowedServices = [ "smart-tv-browse" "smart-tv-control" ];
          }
          {
            scope = "streaming";
            discoveryExports = [ ];
            allowedServices = [ ];
          }
        ];
        sharedServiceMatrix = [
          {
            requesterScopes = [ "consumer" ];
            responderScope = "streaming";
            serviceClass = "media-receiver";
            service = "smart-tv-browse";
            discovery = {
              protocol = "mdns";
              direction = "consumer-to-streaming";
            };
            payload = {
              protocol = "tcp";
              ports = [ 8008 8009 ];
              direction = "consumer-to-streaming";
              returnBehavior = "stateful-return";
            };
          }
          {
            requesterScopes = [ "consumer" ];
            responderScope = "streaming";
            serviceClass = "media-receiver";
            service = "smart-tv-probe";
            discovery = {
              protocol = "ssdp";
              direction = "consumer-to-streaming";
            };
            payload = {
              protocol = "udp";
              ports = [ 1900 ];
              direction = "consumer-to-streaming";
              returnBehavior = "discovery-response-only";
            };
          }
          {
            requesterScopes = [ "consumer" ];
            responderScope = "streaming";
            serviceClass = "media-control";
            service = "smart-tv-control";
            discovery = {
              protocol = "none";
              direction = "not-discovered";
            };
            payload = {
              protocol = "tcp";
              ports = [ 8443 ];
              direction = "consumer-to-streaming";
              returnBehavior = "stateful-return";
            };
          }
          {
            requesterScopes = [ "consumer" ];
            responderScope = "streaming";
            serviceClass = "media-hidden";
            service = "smart-tv-hidden";
            discovery = {
              protocol = "none";
              direction = "not-discovered";
            };
            payload = {
              protocol = "tcp";
              ports = [ 9443 ];
              direction = "consumer-to-streaming";
              returnBehavior = "stateful-return";
            };
          }
        ];
      };

      communicationContract = {
        trafficTypes = [
          { name = "smart-tv-browse"; match = [ { proto = "tcp"; family = "any"; dports = [ 8008 8009 ]; } ]; }
          { name = "smart-tv-probe"; match = [ { proto = "udp"; family = "any"; dports = [ 1900 ]; } ]; }
          { name = "smart-tv-control"; match = [ { proto = "tcp"; family = "any"; dports = [ 8443 ]; } ]; }
          { name = "smart-tv-hidden"; match = [ { proto = "tcp"; family = "any"; dports = [ 9443 ]; } ]; }
        ];
        services = [
          {
            name = "smart-tv-browse";
            providers = [ "tv01" ];
            trafficType = "smart-tv-browse";
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "consumer"; } ];
              responderScope = { kind = "host"; name = "tv01"; tenant = "streaming"; };
              serviceClass = "media-receiver";
              discovery = {
                protocol = "mdns";
                direction = "responder-to-controller";
                advertisedServices = [ "_googlecast._tcp" ];
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
                {
                  from = { kind = "tenant"; name = "consumer"; };
                  to = { kind = "service"; name = "smart-tv-hidden"; };
                  reason = "hidden-service-not-allowed";
                  negativeProbe = "consumer-to-hidden-service";
                }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "pairing-required";
              cloudDependency = "optional";
            };
          }
          {
            name = "smart-tv-probe";
            providers = [ "tv01" ];
            trafficType = "smart-tv-probe";
          }
          {
            name = "smart-tv-control";
            providers = [ "tv01" ];
            trafficType = "smart-tv-control";
          }
          {
            name = "smart-tv-hidden";
            providers = [ "tv01" ];
            trafficType = "smart-tv-hidden";
          }
        ];
        relations = [
          {
            id = "allow-consumer-to-smart-tv-browse";
            priority = 100;
            from = { kind = "tenant"; name = "consumer"; };
            to = { kind = "service"; name = "smart-tv-browse"; };
            trafficType = "smart-tv-browse";
            action = "allow";
          }
          {
            id = "allow-consumer-to-smart-tv-control";
            priority = 110;
            from = { kind = "tenant"; name = "consumer"; };
            to = { kind = "service"; name = "smart-tv-control"; };
            trafficType = "smart-tv-control";
            action = "allow";
          }
          {
            id = "allow-consumer-to-wan";
            priority = 120;
            from = { kind = "tenant"; name = "consumer"; };
            to = { kind = "external"; uplinks = [ "wan" ]; };
            trafficType = "smart-tv-control";
            action = "allow";
          }
        ];
      };

      topology.nodes = {
        access-consumer = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "consumer"; } ];
        };
        access-streaming = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "streaming"; } ];
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
        [ "access-consumer" "downstream" ]
        [ "access-streaming" "downstream" ]
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
  | $discovery.confined[] | select(.scope == "consumer") as $consumer
  | ($consumer.discoveryExports == ["smart-tv-browse", "smart-tv-probe"])
  and ($consumer.allowedServices == ["smart-tv-browse", "smart-tv-control"])
  and (
    ($consumer.discoveryExports | index("smart-tv-browse") != null)
    and ($consumer.allowedServices | index("smart-tv-browse") != null)
  )
  and (
    ($consumer.discoveryExports | index("smart-tv-probe") != null)
    and ($consumer.allowedServices | index("smart-tv-probe") == null)
  )
  and (
    ($consumer.discoveryExports | index("smart-tv-control") == null)
    and ($consumer.allowedServices | index("smart-tv-control") != null)
  )
  and (
    ($consumer.discoveryExports | index("smart-tv-hidden") == null)
    and ($consumer.allowedServices | index("smart-tv-hidden") == null)
    and ($consumer.deniedCrossScopeByDefault == [])
  )
  and (
    $discovery.exported
    | map(select(.service == "smart-tv-browse"))[0]
    | .discovery == { protocol: "mdns", direction: "consumer-to-streaming" }
      and .payload == {
        authorized: true,
        inferredFromDiscovery: false,
        protocol: "tcp",
        ports: [8008, 8009],
        direction: "consumer-to-streaming",
        returnBehavior: "stateful-return"
      }
  )
  and (
    $discovery.exported
    | map(select(.service == "smart-tv-probe"))[0]
    | .discovery == { protocol: "ssdp", direction: "consumer-to-streaming" }
      and .payload == {
        authorized: false,
        inferredFromDiscovery: false,
        protocol: "udp",
        ports: [1900],
        direction: "consumer-to-streaming",
        returnBehavior: "discovery-response-only"
      }
  )
  and (
    $site.services[]
    | select(.name == "smart-tv-browse")
    | .serviceClass == "media-receiver"
      and .discovery == {
        protocol: "mdns",
        direction: "responder-to-controller",
        advertisedServices: ["_googlecast._tcp"]
      }
      and .payload == {
        protocol: "tcp",
        ports: [8008, 8009],
        direction: "controller-to-receiver",
        returnBehavior: "established-only"
      }
      and .authenticationBoundary == "pairing-required"
      and .exposureClass == "internal-shared"
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
    echo "FAIL fs600 discovery payload construction: ${label} compiled" >&2
    exit 1
  fi

  grep -q "$expected_code" "$err"
  grep -q "$expected_text" "$err"
}

expect_failure \
  "missing-authentication-boundary" \
  "authenticationBoundary = \"pairing-required\";" \
  "# authenticationBoundary omitted" \
  "E_SERVICE_POLICY_REQUIRED_FIELD" \
  "service 'smart-tv-browse' servicePolicy is missing required field 'authenticationBoundary'"

expect_failure \
  "missing-exposure-class" \
  "exposureClass = \"internal-shared\";" \
  "# exposureClass omitted" \
  "E_SERVICE_POLICY_REQUIRED_FIELD" \
  "service 'smart-tv-browse' servicePolicy is missing required field 'exposureClass'"

expect_failure \
  "infer-payload-from-discovery" \
  "cloudDependency = \"optional\";" \
  "cloudDependency = \"optional\"; inferPayloadFromDiscovery = true;" \
  "E_SERVICE_POLICY_INFERRED_AUTHORITY" \
  "must not infer authority from 'inferPayloadFromDiscovery'"

expect_failure \
  "grant-payload-from-discovery-export" \
  "protocol = \"ssdp\";" \
  "protocol = \"ssdp\"; grantsPayloadReachability = true;" \
  "E_ACCESS_SPACE_DISCOVERY_PAYLOAD_INFERENCE" \
  "must not grant payload reachability from discovery visibility"

echo "PASS fs600-discovery-payload-construction"
