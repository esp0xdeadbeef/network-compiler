#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-200-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

good_input="${tmp_dir}/fs200-shared-service-good.nix"
good_output="${tmp_dir}/fs200-shared-service-good.json"

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
          { kind = "tenant"; name = "trusted"; ipv4 = "10.20.10.0/24"; }
          { kind = "tenant"; name = "guest"; ipv4 = "10.20.20.0/24"; }
        ];
        endpoints = [
          { kind = "host"; name = "printer01"; tenant = "trusted"; }
        ];
      };

      communicationContract = {
        trafficTypes = [
          { name = "ipp"; match = [ { proto = "tcp"; family = "any"; dports = [ 631 ]; } ]; }
        ];
        services = [
          {
            name = "shared-printer";
            providers = [ "printer01" ];
            trafficType = "ipp";
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "trusted"; } ];
              responderScope = { kind = "host"; name = "printer01"; tenant = "trusted"; };
              serviceClass = "printer";
              discovery = {
                protocol = "mdns";
                direction = "responder-to-requester";
                advertisedServices = [ "_ipp._tcp" "_printer._tcp" ];
              };
              payload = {
                protocol = "ipp";
                ports = [ 631 ];
                direction = "requester-to-responder";
                returnBehavior = "established-only";
              };
              management = {
                allowed = false;
                boundary = "admin-scope-only";
              };
              reverseInitiation = {
                allowed = false;
                boundary = "no-printer-initiated-client-paths";
              };
              deniedPaths = [
                {
                  from = { kind = "tenant"; name = "guest"; };
                  to = { kind = "service"; name = "shared-printer"; };
                  reason = "guest-print-denied";
                  negativeProbe = "guest-to-printer-ipp";
                }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "printer-local-or-print-server";
              cloudDependency = "none";
            };
          }
        ];
        relations = [
          {
            id = "allow-trusted-to-shared-printer";
            priority = 100;
            from = { kind = "tenant"; name = "trusted"; };
            to = { kind = "service"; name = "shared-printer"; };
            trafficType = "ipp";
            action = "allow";
          }
          {
            id = "allow-trusted-to-wan";
            priority = 110;
            from = { kind = "tenant"; name = "trusted"; };
            to = { kind = "external"; uplinks = [ "wan" ]; };
            trafficType = "ipp";
            action = "allow";
          }
        ];
      };

      topology.nodes = {
        access-trusted = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "trusted"; } ];
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
        [ "access-trusted" "downstream" ]
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
  .sites.esp0xdeadbeef."site-a".services as $services
  | ($services | length == 1)
  and (
    $services[0]
    | .name == "shared-printer"
      and .requesterScopes == [{ kind: "tenant", name: "trusted" }]
      and .responderScope == { kind: "host", name: "printer01", tenant: "trusted" }
      and .discovery == {
        protocol: "mdns",
        direction: "responder-to-requester",
        advertisedServices: ["_ipp._tcp", "_printer._tcp"]
      }
      and .payload == {
        protocol: "ipp",
        ports: [631],
        direction: "requester-to-responder",
        returnBehavior: "established-only"
      }
      and .management == { allowed: false, boundary: "admin-scope-only" }
      and .reverseInitiation == { allowed: false, boundary: "no-printer-initiated-client-paths" }
      and .deniedPaths == [{
        from: { kind: "tenant", name: "guest" },
        to: { kind: "service", name: "shared-printer" },
        reason: "guest-print-denied",
        negativeProbe: "guest-to-printer-ipp"
      }]
      and .exposureClass == "internal-shared"
      and .authenticationBoundary == "printer-local-or-print-server"
      and .cloudDependency == "none"
  )
' "$good_output" >/dev/null

expect_required_failure() {
  local label="$1"
  local search="$2"
  local replace="$3"
  local input="${tmp_dir}/${label}.nix"
  local err="${tmp_dir}/${label}.err"

  sed "s/${search}/${replace}/" "$good_input" >"$input"

  set +e
  nix run "$ROOT#compile" -- "$input" 2>"$err" >/dev/null
  local rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL fs200 shared-service exposure: ${label} compiled" >&2
    exit 1
  fi
  grep -q "E_SERVICE_POLICY_REQUIRED_FIELD" "$err"
}

expect_inference_failure() {
  local label="$1"
  local injected_field="$2"
  local expected_code="${3:-E_SERVICE_POLICY_INFERRED_AUTHORITY}"
  local input="${tmp_dir}/${label}.nix"
  local err="${tmp_dir}/${label}.err"

  sed "s/cloudDependency = \"none\";/cloudDependency = \"none\"; ${injected_field} = true;/" \
    "$good_input" >"$input"

  set +e
  nix run "$ROOT#compile" -- "$input" 2>"$err" >/dev/null
  local rc=$?
  set -e
  if [[ "$rc" -eq 0 ]]; then
    echo "FAIL fs200 shared-service exposure: ${label} compiled" >&2
    exit 1
  fi
  grep -q "$expected_code" "$err"
}

expect_required_failure \
  "missing-requester-scopes" \
  "requesterScopes = \\[ { kind = \"tenant\"; name = \"trusted\"; } \\];" \
  "# requesterScopes omitted"

expect_required_failure \
  "missing-responder-scope" \
  "responderScope = { kind = \"host\"; name = \"printer01\"; tenant = \"trusted\"; };" \
  "# responderScope omitted"

expect_required_failure \
  "missing-payload-return-behavior" \
  "returnBehavior = \"established-only\";" \
  "# returnBehavior omitted"

expect_required_failure \
  "missing-denied-paths" \
  "deniedPaths = \\[" \
  "deniedPathsOmitted = ["

expect_required_failure \
  "missing-authentication-boundary" \
  "authenticationBoundary = \"printer-local-or-print-server\";" \
  "# authenticationBoundary omitted"

expect_inference_failure "infer-payload-from-discovery" "inferPayloadFromDiscovery" "DISCOVERY_PAYLOAD_AUTHORIZATION_LEAK"
expect_inference_failure "infer-exposure-from-host-placement" "inferExposureFromHostPlacement"

echo "PASS fs200-shared-service-exposure-boundary"
