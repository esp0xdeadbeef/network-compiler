#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-620-HDS-010-SDS-010-SMS-010
# GAMP-ID: FS-620-HDS-010-SDS-010-SMS-020
# GAMP-ID: FS-620-HDS-010-SDS-010-SMS-030
# GAMP-ID: FS-620-HDS-010-SDS-010-SMS-040
# GAMP-ID: FS-630-HDS-010-SDS-010-SMS-010
# GAMP-ID: FS-630-HDS-010-SDS-010-SMS-020
# GAMP-ID: FS-630-HDS-010-SDS-010-SMS-030
# GAMP-ID: FS-630-HDS-010-SDS-010-SMS-040
# GAMP-ID: FS-640-HDS-010-SDS-010-SMS-010
# GAMP-ID: FS-640-HDS-010-SDS-010-SMS-020
# GAMP-ID: FS-640-HDS-010-SDS-010-SMS-030
# GAMP-ID: FS-640-HDS-010-SDS-010-SMS-040
# GAMP-ID: FS-640-HDS-010-SDS-010-SMS-050
# GAMP-ID: FS-670-HDS-010-SDS-010-SMS-030
# GAMP-ID: FS-670-HDS-010-SDS-010-SMS-040
# GAMP-ID: FS-680-HDS-010-SDS-010-SMS-010
# GAMP-ID: FS-680-HDS-010-SDS-010-SMS-020
# GAMP-ID: FS-680-HDS-010-SDS-010-SMS-030
# GAMP-ID: FS-680-HDS-010-SDS-010-SMS-040
# GAMP-ID: FS-680-HDS-010-SDS-010-SMS-050
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

good_input="${tmp_dir}/shared-service-policy-good.nix"
good_output="${tmp_dir}/shared-service-policy-good.json"
bad_underlay_input="${tmp_dir}/shared-service-policy-underlay-inference.nix"
bad_client_path_input="${tmp_dir}/shared-service-policy-client-path-inference.nix"

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
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "shared-printer"; }; reason = "guest-print-denied"; negativeProbe = "guest-to-printer-ipp"; }
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
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "tenant"; name = "trusted"; }; reason = "guest-to-trusted-denied"; negativeProbe = "guest-to-trusted-cast"; }
                { from = { kind = "tenant"; name = "media"; }; to = { kind = "tenant"; name = "trusted"; }; reason = "reverse-discovery-denied"; negativeProbe = "receiver-to-controller-mdns"; }
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
            id = "allow-trusted-to-wan";
            priority = 120;
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
  .sites.esp0xdeadbeef."site-a".services as $services
  | ($services | length == 2)
  and (
    $services[]
    | select(.name == "shared-printer")
    | .serviceClass == "printer"
      and .requesterScopes == [{ kind: "tenant", name: "trusted" }]
      and .responderScope == { kind: "host", name: "printer01", tenant: "trusted" }
      and .discovery == { protocol: "mdns", direction: "responder-to-requester", advertisedServices: ["_ipp._tcp", "_printer._tcp"] }
      and .payload == { protocol: "ipp", ports: [631], direction: "requester-to-responder", returnBehavior: "established-only" }
      and .management == { allowed: false, boundary: "admin-scope-only" }
      and .reverseInitiation == { allowed: false, boundary: "no-printer-initiated-client-paths" }
      and (.deniedPaths | length == 1)
      and .exposureClass == "internal-shared"
      and .authenticationBoundary == "printer-local-or-print-server"
      and .cloudDependency == "none"
  )
  and (
    $services[]
    | select(.name == "media-receiver")
    | .serviceClass == "media-receiver"
      and .discovery.protocol == "mdns"
      and .payload.ports == [7000, 7100]
      and .reverseInitiation.allowed == false
      and (.deniedPaths | length == 2)
      and .cloudDependency == "optional"
  )
' "$good_output" >/dev/null

sed 's/cloudDependency = "none";/cloudDependency = "none"; inferAuthorityFromUnderlay = true;/' \
  "$good_input" >"$bad_underlay_input"

set +e
nix run "$ROOT#compile" -- "$bad_underlay_input" 2>"${tmp_dir}/underlay.err" >/dev/null
underlay_rc=$?
set -e
if [[ "$underlay_rc" -eq 0 ]]; then
  echo "FAIL shared-service-policy: underlay authority inference compiled" >&2
  exit 1
fi
grep -q "E_SERVICE_POLICY_INFERRED_AUTHORITY" "${tmp_dir}/underlay.err"

sed 's/cloudDependency = "none";/cloudDependency = "none"; inferClientPaths = true;/' \
  "$good_input" >"$bad_client_path_input"

set +e
nix run "$ROOT#compile" -- "$bad_client_path_input" 2>"${tmp_dir}/client-path.err" >/dev/null
client_path_rc=$?
set -e
if [[ "$client_path_rc" -eq 0 ]]; then
  echo "FAIL shared-service-policy: client-path inference compiled" >&2
  exit 1
fi
grep -q "E_SERVICE_POLICY_INFERRED_AUTHORITY" "${tmp_dir}/client-path.err"
