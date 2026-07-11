#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-620-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

good_input="${tmp_dir}/fs620-client-isolation-classification.nix"
good_output="${tmp_dir}/fs620-client-isolation-classification.json"
missing_boundary_input="${tmp_dir}/fs620-client-isolation-missing-boundary.nix"
missing_limits_input="${tmp_dir}/fs620-client-isolation-missing-limits.nix"
unknown_endpoint_input="${tmp_dir}/fs620-client-isolation-unknown-endpoint.nix"

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
          { kind = "tenant"; name = "media"; ipv4 = "10.20.30.0/24"; }
        ];
        endpoints = [
          { kind = "host"; name = "laptop01"; tenant = "trusted"; }
          { kind = "host"; name = "printer01"; tenant = "trusted"; }
          { kind = "host"; name = "receiver01"; tenant = "media"; }
        ];
      };

      communicationContract = {
        trafficTypes = [
          { name = "ipp"; match = [ { proto = "tcp"; family = "any"; dports = [ 631 ]; } ]; }
          { name = "airplay"; match = [ { proto = "tcp"; family = "any"; dports = [ 7000 7100 ]; } ]; }
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
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "shared-printer"; }; reason = "guest-print-denied"; }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "printer-local-or-print-server";
              cloudDependency = "none";
            };
          }
          {
            name = "media-receiver";
            providers = [ "receiver01" ];
            trafficType = "airplay";
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "trusted"; } ];
              responderScope = { kind = "host"; name = "receiver01"; tenant = "media"; };
              serviceClass = "media-receiver";
              discovery = {
                protocol = "mdns";
                direction = "responder-to-controller";
                advertisedServices = [ "_airplay._tcp" "_raop._tcp" ];
              };
              payload = {
                protocol = "airplay";
                ports = [ 7000 7100 ];
                direction = "controller-to-receiver";
                returnBehavior = "established-only";
              };
              management = {
                allowed = false;
                boundary = "receiver-management-denied";
              };
              reverseInitiation = {
                allowed = false;
                boundary = "no-receiver-initiated-controller-paths";
              };
              deniedPaths = [
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "media-receiver"; }; reason = "guest-receiver-denied"; negativeProbe = "guest-to-receiver"; }
                { kind = "media-to-management"; from = { kind = "tenant"; name = "media"; }; to = { kind = "management"; name = "media-receiver"; }; reason = "media-to-management-denied"; negativeProbe = "media-to-management"; }
                { from = { kind = "tenant"; name = "media"; }; to = { kind = "tenant"; name = "trusted"; }; reason = "reverse-discovery-denied"; }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "receiver-pairing";
              cloudDependency = "optional";
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
            id = "allow-trusted-to-media-receiver";
            priority = 110;
            from = { kind = "tenant"; name = "trusted"; };
            to = { kind = "service"; name = "media-receiver"; };
            trafficType = "airplay";
            action = "allow";
          }
          {
            id = "deny-guest-to-trusted";
            priority = 120;
            from = { kind = "tenant"; name = "guest"; };
            to = { kind = "tenant"; name = "trusted"; };
            trafficType = "any";
            action = "deny";
          }
          {
            id = "allow-trusted-to-wan";
            priority = 130;
            from = { kind = "tenant"; name = "trusted"; };
            to = { kind = "external"; uplinks = [ "wan" ]; };
            trafficType = "any";
            action = "allow";
          }
        ];
        isolationDecisions = [
          {
            id = "trusted-same-access-service-limited";
            scope = "intra-access";
            classification = "service-limited";
            from = { kind = "client"; name = "laptop01"; };
            to = { kind = "client"; name = "printer01"; };
            boundary = "trusted-access-policy";
            serviceLimits = [ "ipp:tcp/631" ];
            serviceNames = [ "shared-printer" ];
            relationIds = [ "allow-trusted-to-shared-printer" ];
            trafficTypes = [ "ipp" ];
          }
          {
            id = "trusted-same-tenant-denied-by-default";
            scope = "intra-tenant";
            classification = "denied";
            from = { kind = "tenant"; name = "trusted"; };
            to = { kind = "tenant"; name = "trusted"; };
            boundary = "deny-lateral-by-default";
          }
          {
            id = "trusted-to-media-service-limited";
            scope = "intra-tenant";
            classification = "service-limited";
            from = { kind = "tenant"; name = "trusted"; };
            to = { kind = "tenant"; name = "media"; };
            boundary = "policy-shared-service-lane";
            serviceLimits = [ "airplay:tcp/7000" "airplay:tcp/7100" ];
            serviceNames = [ "media-receiver" ];
            relationIds = [ "allow-trusted-to-media-receiver" ];
            trafficTypes = [ "airplay" ];
          }
          {
            id = "guest-to-trusted-denied";
            scope = "intra-tenant";
            classification = "denied";
            from = { kind = "tenant"; name = "guest"; };
            to = { kind = "tenant"; name = "trusted"; };
            boundary = "guest-trusted-policy-deny";
            relationIds = [ "deny-guest-to-trusted" ];
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
        access-media = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "media"; } ];
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
        [ "access-media" "downstream" ]
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
  | ($site.consumedInterfaces.access | sort_by(.access, .tenant)) == [
      { access: "access-guest", tenant: "guest" },
      { access: "access-media", tenant: "media" },
      { access: "access-trusted", tenant: "trusted" }
    ]
  and (
    $site.consumedInterfaces.clients[]
    | select(.client == "laptop01")
    | .tenant == "trusted" and .access == ["access-trusted"]
  )
  and (
    $site.consumedInterfaces.sharedServices[]
    | select(.service == "shared-printer")
    | .requesterScopes == [{ kind: "tenant", name: "trusted" }]
      and .responderScope == { kind: "host", name: "printer01", tenant: "trusted" }
      and .payload.ports == [631]
      and .deniedPaths[0].reason == "guest-print-denied"
  )
  and (
    [$site.isolationDecisions[] | select(.classification == "service-limited")] | length == 2
  )
  and (
    $site.isolationDecisions[]
    | select(.id == "trusted-same-access-service-limited")
    | .scope == "intra-access"
      and .from == { kind: "client", name: "laptop01" }
      and .to == { kind: "client", name: "printer01" }
      and .boundary == "trusted-access-policy"
      and .serviceLimits == ["ipp:tcp/631"]
      and .relationshipInputs.serviceNames == ["shared-printer"]
  )
  and (
    $site.isolationDecisions[]
    | select(.id == "guest-to-trusted-denied")
    | .classification == "denied"
      and .relationshipInputs.relationIds == ["deny-guest-to-trusted"]
  )
  and (
    $site.sourceAudit.behavior[]
    | select(.outputPath == ["isolationDecisions", 0])
    | .sourcePath == ["communicationContract", "isolationDecisions", 0]
      and .authority == "network-compiler"
  )
' "$good_output" >/dev/null

sed 's/boundary = "trusted-access-policy";/boundary = "";/' \
  "$good_input" >"$missing_boundary_input"

set +e
nix run "$ROOT#compile" -- "$missing_boundary_input" 2>"${tmp_dir}/missing-boundary.err" >/dev/null
missing_boundary_rc=$?
set -e
if [[ "$missing_boundary_rc" -eq 0 ]]; then
  echo "FAIL fs620 isolation: missing boundary compiled" >&2
  exit 1
fi
grep -q "E_ISOLATION_BOUNDARY_REQUIRED" "${tmp_dir}/missing-boundary.err"

sed 's/serviceLimits = \[ "ipp:tcp\/631" \];//' \
  "$good_input" >"$missing_limits_input"

set +e
nix run "$ROOT#compile" -- "$missing_limits_input" 2>"${tmp_dir}/missing-limits.err" >/dev/null
missing_limits_rc=$?
set -e
if [[ "$missing_limits_rc" -eq 0 ]]; then
  echo "FAIL fs620 isolation: missing service limits compiled" >&2
  exit 1
fi
grep -q "E_ISOLATION_SERVICE_LIMITS_REQUIRED" "${tmp_dir}/missing-limits.err"

sed 's/from = { kind = "client"; name = "laptop01"; };/from = { kind = "client"; name = "ghost01"; };/' \
  "$good_input" >"$unknown_endpoint_input"

set +e
nix run "$ROOT#compile" -- "$unknown_endpoint_input" 2>"${tmp_dir}/unknown-endpoint.err" >/dev/null
unknown_endpoint_rc=$?
set -e
if [[ "$unknown_endpoint_rc" -eq 0 ]]; then
  echo "FAIL fs620 isolation: unknown endpoint compiled" >&2
  exit 1
fi
grep -q "E_ISOLATION_ENDPOINT_UNKNOWN" "${tmp_dir}/unknown-endpoint.err"
