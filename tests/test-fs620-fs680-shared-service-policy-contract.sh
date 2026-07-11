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
                { kind = "media-to-management"; from = { kind = "tenant"; name = "media"; }; to = { kind = "management"; name = "media-receiver"; }; reason = "media-to-management-denied"; negativeProbe = "media-to-management"; }
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
      and (.deniedPaths | length == 3)
      and any(.deniedPaths[]; .kind == "media-to-management")
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
grep -q "UNDERLAY_USED_AS_TENANT_PAYLOAD_AUTHORITY" "${tmp_dir}/underlay.err"

# --- FS-620-HDS-010-SDS-010-SMS-030 N2: overlay underlay → resolver authority rejection ---
resolver_underlay_input="${tmp_dir}/resolver-underlay.nix"

cat >"$resolver_underlay_input" <<'NIX'
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
        ];
        endpoints = [
          { kind = "host"; name = "resolver01"; tenant = "trusted"; }
        ];
      };
      communicationContract = {
        trafficTypes = [
          { name = "dns"; match = [ { proto = "udp"; family = "any"; dports = [ 53 ]; } ]; }
        ];
        services = [
          {
            name = "shared-resolver";
            providers = [ "resolver01" ];
            trafficType = "dns";
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "trusted"; } ];
              responderScope = { kind = "host"; name = "resolver01"; tenant = "trusted"; };
              serviceClass = "dns";
              inferAuthorityFromUnderlay = true;
              discovery = {
                protocol = "dns";
                direction = "responder-to-requester";
                advertisedServices = [ "_dns._udp" ];
              };
              payload = {
                protocol = "dns";
                ports = [ 53 ];
                direction = "bidirectional";
                returnBehavior = "established-only";
              };
              management = { allowed = false; boundary = "admin-scope-only"; };
              reverseInitiation = { allowed = false; boundary = "no-resolver-initiated-paths"; };
              deniedPaths = [
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "shared-resolver"; }; reason = "guest-resolver-denied"; negativeProbe = "guest-to-resolver-dns"; }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "resolver-local";
              cloudDependency = "none";
            };
          }
        ];
        relations = [
          {
            id = "allow-trusted-to-resolver";
            priority = 100;
            from = { kind = "tenant"; name = "trusted"; };
            to = { kind = "service"; name = "shared-resolver"; };
            trafficType = "dns";
            action = "allow";
          }
          {
            id = "allow-trusted-to-wan";
            priority = 200;
            from = { kind = "tenant"; name = "trusted"; };
            to = { kind = "external"; uplinks = [ "wan" ]; };
            trafficType = "dns";
            action = "allow";
          }
        ];
      };
      topology.nodes = {
        access-trusted = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "trusted"; } ];
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
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
NIX

set +e
nix run "$ROOT#compile" -- "$resolver_underlay_input" 2>"${tmp_dir}/resolver-underlay.err" >/dev/null
resolver_underlay_rc=$?
set -e
if [[ "$resolver_underlay_rc" -eq 0 ]]; then
  echo "FAIL shared-service-policy: resolver underlay inference compiled" >&2
  exit 1
fi
grep -q "UNDERLAY_USED_AS_RESOLVER_OR_DISCOVERY_AUTHORITY" "${tmp_dir}/resolver-underlay.err"

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

# --- FS-630-HDS-010-SDS-010-SMS-010: printer discovery service identity seeded negatives ---
printer_no_requester_input="${tmp_dir}/printer-no-requester.nix"
printer_infer_discovery_input="${tmp_dir}/printer-infer-discovery.nix"

# SN1: Missing requester scope — expect E_SERVICE_POLICY_REQUIRED_FIELD
cat >"$printer_no_requester_input" <<'NIX'
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
              management = { allowed = false; boundary = "admin-scope-only"; };
              reverseInitiation = { allowed = false; boundary = "no-printer-initiated-client-paths"; };
              deniedPaths = [
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "shared-printer"; }; reason = "guest-print-denied"; negativeProbe = "guest-to-printer-ipp"; }
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
            priority = 200;
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
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
NIX

set +e
nix run "$ROOT#compile" -- "$printer_no_requester_input" 2>"${tmp_dir}/printer-no-requester.err" >/dev/null
printer_no_requester_rc=$?
set -e
if [[ "$printer_no_requester_rc" -eq 0 ]]; then
  echo "FAIL FS-630-HDS-010-SDS-010-SMS-010 SN1: printer compiled with missing requesterScopes" >&2
  exit 1
fi
grep -q "E_SERVICE_POLICY_REQUIRED_FIELD" "${tmp_dir}/printer-no-requester.err"

# SN2: inferDiscoveryFromPayload flag — expect E_SERVICE_POLICY_INFERRED_AUTHORITY
sed 's/cloudDependency = \"none\";/cloudDependency = \"none\"; inferDiscoveryFromPayload = true;/' \
  "$good_input" >"$printer_infer_discovery_input"

set +e
nix run "$ROOT#compile" -- "$printer_infer_discovery_input" 2>"${tmp_dir}/printer-infer-discovery.err" >/dev/null
printer_infer_discovery_rc=$?
set -e
if [[ "$printer_infer_discovery_rc" -eq 0 ]]; then
  echo "FAIL FS-630-HDS-010-SDS-010-SMS-010 SN2: printer compiled with inferDiscoveryFromPayload" >&2
  exit 1
fi
grep -q "E_SERVICE_POLICY_INFERRED_AUTHORITY" "${tmp_dir}/printer-infer-discovery.err"

# --- FS-630-HDS-010-SDS-010-SMS-040: printer denied-path preservation seeded negatives ---
printer_empty_denied_input="${tmp_dir}/printer-empty-denied.nix"
printer_infer_denied_input="${tmp_dir}/printer-infer-denied.nix"

# SN1: Printer service with empty deniedPaths → expect MISSING_DENIED_PATH_DATA
cat >"$printer_empty_denied_input" <<'NIX'
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
          { kind = "host"; name = "printer02"; tenant = "trusted"; }
        ];
      };
      communicationContract = {
        trafficTypes = [
          { name = "ipp"; match = [ { proto = "tcp"; family = "any"; dports = [ 631 ]; } ]; }
        ];
        services = [
          {
            name = "office-printer";
            providers = [ "printer02" ];
            trafficType = "ipp";
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "trusted"; } ];
              responderScope = { kind = "host"; name = "printer02"; tenant = "trusted"; };
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
              management = { allowed = false; boundary = "admin-scope-only"; };
              reverseInitiation = { allowed = false; boundary = "no-printer-initiated-client-paths"; };
              deniedPaths = [
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "printer-local-or-print-server";
              cloudDependency = "none";
            };
          }
        ];
        relations = [
          {
            id = "allow-trusted-to-office-printer";
            priority = 100;
            from = { kind = "tenant"; name = "trusted"; };
            to = { kind = "service"; name = "office-printer"; };
            trafficType = "ipp";
            action = "allow";
          }
          {
            id = "allow-trusted-to-wan";
            priority = 200;
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

set +e
nix run "$ROOT#compile" -- "$printer_empty_denied_input" 2>"${tmp_dir}/printer-empty-denied.err" >/dev/null
printer_empty_denied_rc=$?
set -e
if [[ "$printer_empty_denied_rc" -eq 0 ]]; then
  echo "FAIL FS-630-HDS-010-SDS-010-SMS-040 SN1: printer compiled with empty deniedPaths" >&2
  exit 1
fi
grep -q "MISSING_DENIED_PATH_DATA" "${tmp_dir}/printer-empty-denied.err"

# SN2: inferDeniedPathsFromPayload flag → expect E_SERVICE_POLICY_INFERRED_AUTHORITY
sed 's/cloudDependency = "none";/cloudDependency = "none"; inferDeniedPathsFromPayload = true;/' \
  "$good_input" >"$printer_infer_denied_input"

set +e
nix run "$ROOT#compile" -- "$printer_infer_denied_input" 2>"${tmp_dir}/printer-infer-denied.err" >/dev/null
printer_infer_denied_rc=$?
set -e
if [[ "$printer_infer_denied_rc" -eq 0 ]]; then
  echo "FAIL FS-630-HDS-010-SDS-010-SMS-040 SN2: printer compiled with inferDeniedPathsFromPayload" >&2
  exit 1
fi
grep -q "E_SERVICE_POLICY_INFERRED_AUTHORITY" "${tmp_dir}/printer-infer-denied.err"

# --- FS-640-HDS-010-SDS-010-SMS-040: media management boundary seeded negatives ---
media_mgmt_good_input="${tmp_dir}/media-mgmt-good.nix"
media_mgmt_inferred_input="${tmp_dir}/media-mgmt-inferred.nix"
media_mgmt_denied_path_input="${tmp_dir}/media-mgmt-denied-path.nix"

cat >"$media_mgmt_good_input" <<'NIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };
      ownership = {
        prefixes = [
          { kind = "tenant"; name = "media"; ipv4 = "10.20.30.0/24"; }
        ];
        endpoints = [
          { kind = "host"; name = "living-room-cast"; tenant = "media"; }
        ];
      };
      communicationContract = {
        trafficTypes = [
          { name = "cast"; match = [ { proto = "tcp"; family = "any"; dports = [ 8000 ]; } ]; }
        ];
        services = [
          {
            name = "living-room-cast";
            providers = [ "living-room-cast" ];
            trafficType = "cast";
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "media"; } ];
              responderScope = { kind = "host"; name = "living-room-cast"; tenant = "media"; };
              serviceClass = "media-receiver";
              discovery = {
                protocol = "mdns";
                direction = "responder-to-controller";
                advertisedServices = [ "_cast._tcp" ];
              };
              payload = {
                protocol = "cast";
                ports = [ 8000 ];
                direction = "controller-to-receiver";
                returnBehavior = "established-only";
              };
              management = {
                allowed = true;
                boundary = "admin-scope-only";
              };
              managementAccessPolicy = {
                sourceScope = { kind = "tenant"; name = "admin"; };
                protocol = "https";
                port = 443;
              };
              reverseInitiation = {
                allowed = false;
                boundary = "no-reverse";
              };
              deniedPaths = [
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "living-room-cast"; }; reason = "guest-to-media-denied"; negativeProbe = "guest-to-cast"; }
                { kind = "media-to-management"; from = { kind = "tenant"; name = "media"; }; to = { kind = "management"; name = "living-room-cast"; }; reason = "media-to-management-denied"; negativeProbe = "media-to-management"; }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "receiver-pairing";
              cloudDependency = "optional";
            };
          }
        ];
        relations = [
          {
            id = "allow-media-to-receiver";
            priority = 100;
            from = { kind = "tenant"; name = "media"; };
            to = { kind = "service"; name = "living-room-cast"; };
            trafficType = "cast";
            action = "allow";
          }
          {
            id = "allow-media-to-wan";
            priority = 200;
            from = { kind = "tenant"; name = "media"; };
            to = { kind = "external"; uplinks = [ "wan" ]; };
            trafficType = "cast";
            action = "allow";
          }
        ];
      };
      topology.nodes = {
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
        [ "access-media" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
NIX

# Positive: management.allowed=true WITH managementAccessPolicy compiles correctly
nix run "$ROOT#compile" -- "$media_mgmt_good_input" >"${tmp_dir}/mgmt-good-out.json" 2>/dev/null
jq -e '
  .sites.esp0xdeadbeef."site-a".services[0].management == { allowed: true, boundary: "admin-scope-only" }
  and .sites.esp0xdeadbeef."site-a".services[0].managementAccessPolicy.sourceScope.name == "admin"
' "${tmp_dir}/mgmt-good-out.json" >/dev/null

# Negative 1: management.allowed=true but no managementAccessPolicy (MANAGEMENT_INFERRED_FROM_PAYLOAD)
cat >"$media_mgmt_inferred_input" <<'NIN'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };
      ownership = {
        prefixes = [
          { kind = "tenant"; name = "media"; ipv4 = "10.20.30.0/24"; }
        ];
        endpoints = [
          { kind = "host"; name = "living-room-cast"; tenant = "media"; }
        ];
      };
      communicationContract = {
        trafficTypes = [
          { name = "cast"; match = [ { proto = "tcp"; family = "any"; dports = [ 8000 ]; } ]; }
        ];
        services = [
          {
            name = "living-room-cast";
            providers = [ "living-room-cast" ];
            trafficType = "cast";
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "media"; } ];
              responderScope = { kind = "host"; name = "living-room-cast"; tenant = "media"; };
              serviceClass = "media-receiver";
              discovery = {
                protocol = "mdns";
                direction = "responder-to-controller";
                advertisedServices = [ "_cast._tcp" ];
              };
              payload = {
                protocol = "cast";
                ports = [ 8000 ];
                direction = "controller-to-receiver";
                returnBehavior = "established-only";
              };
              management = {
                allowed = true;
                boundary = "inferred-no-backing-policy";
              };
              reverseInitiation = {
                allowed = false;
                boundary = "no-reverse";
              };
              deniedPaths = [
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "living-room-cast"; }; reason = "guest-to-media-denied"; negativeProbe = "guest-to-cast"; }
                { kind = "media-to-management"; from = { kind = "tenant"; name = "media"; }; to = { kind = "management"; name = "living-room-cast"; }; reason = "media-to-management-denied"; negativeProbe = "media-to-management"; }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "receiver-pairing";
              cloudDependency = "optional";
            };
          }
        ];
        relations = [
          {
            id = "allow-media-to-receiver";
            priority = 100;
            from = { kind = "tenant"; name = "media"; };
            to = { kind = "service"; name = "living-room-cast"; };
            trafficType = "cast";
            action = "allow";
          }
          {
            id = "allow-media-to-wan";
            priority = 200;
            from = { kind = "tenant"; name = "media"; };
            to = { kind = "external"; uplinks = [ "wan" ]; };
            trafficType = "cast";
            action = "allow";
          }
        ];
      };
      topology.nodes = {
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
        [ "access-media" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
NIN

set +e
nix run "$ROOT#compile" -- "$media_mgmt_inferred_input" 2>"${tmp_dir}/mgmt-inferred.err" >/dev/null
mgmt_inferred_rc=$?
set -e
if [[ "$mgmt_inferred_rc" -eq 0 ]]; then
  echo "FAIL FS-640-HDS-010-SDS-010-SMS-040: management.allowed=true compiled without managementAccessPolicy" >&2
  exit 1
fi
grep -q "MANAGEMENT_INFERRED_FROM_PAYLOAD" "${tmp_dir}/mgmt-inferred.err"

# Negative 2: management.allowed=false but deniedPaths is empty (MISSING_DENIED_PATH_DATA)
cat >"$media_mgmt_denied_path_input" <<'FIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };
      ownership = {
        prefixes = [
          { kind = "tenant"; name = "media"; ipv4 = "10.20.30.0/24"; }
        ];
        endpoints = [
          { kind = "host"; name = "office-speaker"; tenant = "media"; }
        ];
      };
      communicationContract = {
        trafficTypes = [
          { name = "audio"; match = [ { proto = "tcp"; family = "any"; dports = [ 5000 ]; } ]; }
        ];
        services = [
          {
            name = "office-speaker";
            providers = [ "office-speaker" ];
            trafficType = "audio";
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "media"; } ];
              responderScope = { kind = "host"; name = "office-speaker"; tenant = "media"; };
              serviceClass = "media-receiver";
              discovery = {
                protocol = "mdns";
                direction = "responder-to-controller";
                advertisedServices = [ "_audio._tcp" ];
              };
              payload = {
                protocol = "audio";
                ports = [ 5000 ];
                direction = "controller-to-receiver";
                returnBehavior = "established-only";
              };
              management = {
                allowed = false;
                boundary = "speaker-management-denied";
              };
              reverseInitiation = {
                allowed = false;
                boundary = "no-reverse";
              };
              deniedPaths = [
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "speaker-pairing";
              cloudDependency = "none";
            };
          }
        ];
        relations = [
          {
            id = "allow-media-to-speaker";
            priority = 100;
            from = { kind = "tenant"; name = "media"; };
            to = { kind = "service"; name = "office-speaker"; };
            trafficType = "audio";
            action = "allow";
          }
          {
            id = "allow-media-to-wan";
            priority = 200;
            from = { kind = "tenant"; name = "media"; };
            to = { kind = "external"; uplinks = [ "wan" ]; };
            trafficType = "audio";
            action = "allow";
          }
        ];
      };
      topology.nodes = {
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
        [ "access-media" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
FIX

set +e
nix run "$ROOT#compile" -- "$media_mgmt_denied_path_input" 2>"${tmp_dir}/mgmt-denied-path.err" >/dev/null
mgmt_denied_path_rc=$?
set -e
if [[ "$mgmt_denied_path_rc" -eq 0 ]]; then
  echo "FAIL FS-640-HDS-010-SDS-010-SMS-040: management denied compiled with empty deniedPaths" >&2
  exit 1
fi
grep -q "MISSING_DENIED_PATH_DATA" "${tmp_dir}/mgmt-denied-path.err"

# --- FS-640-HDS-010-SDS-010-SMS-050: media denied-path preservation seeded negatives ---
media_dp_missing_input="${tmp_dir}/media-dp-missing.nix"
media_dp_overwrite_input="${tmp_dir}/media-dp-overwrite.nix"
media_dp_good_input="${tmp_dir}/media-dp-good.nix"

# SN2: clearDeniedPaths flag set to true — expect MEDIA_DENIED_PATH_OVERWRITTEN
cat >"$media_dp_overwrite_input" <<'MO1'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };
      ownership = {
        prefixes = [
          { kind = "tenant"; name = "media"; ipv4 = "10.20.30.0/24"; }
        ];
        endpoints = [
          { kind = "host"; name = "living-room-cast"; tenant = "media"; }
        ];
      };
      communicationContract = {
        trafficTypes = [
          { name = "cast"; match = [ { proto = "tcp"; family = "any"; dports = [ 8000 ]; } ]; }
        ];
        services = [
          {
            name = "living-room-cast";
            providers = [ "living-room-cast" ];
            trafficType = "cast";
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "media"; } ];
              responderScope = { kind = "host"; name = "living-room-cast"; tenant = "media"; };
              serviceClass = "media-receiver";
              discovery = {
                protocol = "mdns";
                direction = "responder-to-controller";
                advertisedServices = [ "_cast._tcp" ];
              };
              payload = {
                protocol = "cast";
                ports = [ 8000 ];
                direction = "controller-to-receiver";
                returnBehavior = "established-only";
              };
              management = {
                allowed = false;
                boundary = "no-management";
              };
              reverseInitiation = {
                allowed = false;
                boundary = "no-reverse";
              };
              deniedPaths = [
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "living-room-cast"; }; reason = "guest-to-media-denied"; negativeProbe = "guest-to-cast"; }
                { kind = "media-to-management"; from = { kind = "tenant"; name = "media"; }; to = { kind = "management"; name = "living-room-cast"; }; reason = "media-to-management-denied"; negativeProbe = "media-to-management"; }
              ];
              clearDeniedPaths = true;
              exposureClass = "internal-shared";
              authenticationBoundary = "receiver-pairing";
              cloudDependency = "optional";
            };
          }
        ];
        relations = [
          {
            id = "allow-media-to-receiver";
            priority = 100;
            from = { kind = "tenant"; name = "media"; };
            to = { kind = "service"; name = "living-room-cast"; };
            trafficType = "cast";
            action = "allow";
          }
        ];
      };
      topology.nodes = {
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
        [ "access-media" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
MO1

set +e
nix run "$ROOT#compile" -- "$media_dp_overwrite_input" 2>"${tmp_dir}/media-dp-overwrite.err" >/dev/null
media_dp_overwrite_rc=$?
set -e
if [[ "$media_dp_overwrite_rc" -eq 0 ]]; then
  echo "FAIL FS-640-HDS-010-SDS-010-SMS-050 SN2: media-receiver compiled with clearDeniedPaths=true" >&2
  exit 1
fi
grep -q "MEDIA_DENIED_PATH_OVERWRITTEN" "${tmp_dir}/media-dp-overwrite.err"

# SN1: guest-to-trusted denied path omitted — expect MEDIA_DENIED_PATH_MISSING
cat >"$media_dp_missing_input" <<'MO2'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };
      ownership = {
        prefixes = [
          { kind = "tenant"; name = "media"; ipv4 = "10.20.30.0/24"; }
          { kind = "tenant"; name = "guest"; ipv4 = "10.20.40.0/24"; }
        ];
        endpoints = [
          { kind = "host"; name = "living-room-cast"; tenant = "media"; }
        ];
      };
      communicationContract = {
        trafficTypes = [
          { name = "cast"; match = [ { proto = "tcp"; family = "any"; dports = [ 8000 ]; } ]; }
        ];
        services = [
          {
            name = "living-room-cast";
            providers = [ "living-room-cast" ];
            trafficType = "cast";
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "media"; } ];
              responderScope = { kind = "host"; name = "living-room-cast"; tenant = "media"; };
              serviceClass = "media-receiver";
              discovery = {
                protocol = "mdns";
                direction = "responder-to-controller";
                advertisedServices = [ "_cast._tcp" ];
              };
              payload = {
                protocol = "cast";
                ports = [ 8000 ];
                direction = "controller-to-receiver";
                returnBehavior = "established-only";
              };
              management = {
                allowed = false;
                boundary = "no-management";
              };
              reverseInitiation = {
                allowed = false;
                boundary = "no-reverse";
              };
              deniedPaths = [
                { from = { kind = "tenant"; name = "media"; }; to = { kind = "tenant"; name = "unrelated"; }; reason = "media-to-unrelated-denied"; negativeProbe = "media-to-unrelated"; }
                { kind = "media-to-management"; from = { kind = "tenant"; name = "media"; }; to = { kind = "management"; name = "living-room-cast"; }; reason = "media-to-management-denied"; negativeProbe = "media-to-management"; }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "receiver-pairing";
              cloudDependency = "optional";
            };
          }
        ];
        relations = [
          {
            id = "allow-media-to-receiver";
            priority = 100;
            from = { kind = "tenant"; name = "media"; };
            to = { kind = "service"; name = "living-room-cast"; };
            trafficType = "cast";
            action = "allow";
          }
        ];
      };
      topology.nodes = {
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
        [ "access-media" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
MO2

set +e
nix run "$ROOT#compile" -- "$media_dp_missing_input" 2>"${tmp_dir}/media-dp-missing.err" >/dev/null
media_dp_missing_rc=$?
set -e
if [[ "$media_dp_missing_rc" -eq 0 ]]; then
  echo "FAIL FS-640-HDS-010-SDS-010-SMS-050 SN1: media-receiver compiled without guest denied path" >&2
  exit 1
fi
grep -q "MEDIA_DENIED_PATH_MISSING" "${tmp_dir}/media-dp-missing.err"

# Positive: media-receiver with guest-to-trusted denied path present — compiles successfully
cat >"$media_dp_good_input" <<'MO3'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };
      ownership = {
        prefixes = [
          { kind = "tenant"; name = "media"; ipv4 = "10.20.30.0/24"; }
          { kind = "tenant"; name = "guest"; ipv4 = "10.20.40.0/24"; }
        ];
        endpoints = [
          { kind = "host"; name = "living-room-cast"; tenant = "media"; }
        ];
      };
      communicationContract = {
        trafficTypes = [
          { name = "cast"; match = [ { proto = "tcp"; family = "any"; dports = [ 8000 ]; } ]; }
        ];
        services = [
          {
            name = "living-room-cast";
            providers = [ "living-room-cast" ];
            trafficType = "cast";
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "media"; } ];
              responderScope = { kind = "host"; name = "living-room-cast"; tenant = "media"; };
              serviceClass = "media-receiver";
              discovery = {
                protocol = "mdns";
                direction = "responder-to-controller";
                advertisedServices = [ "_cast._tcp" ];
              };
              payload = {
                protocol = "cast";
                ports = [ 8000 ];
                direction = "controller-to-receiver";
                returnBehavior = "established-only";
              };
              management = {
                allowed = false;
                boundary = "no-management";
              };
              reverseInitiation = {
                allowed = false;
                boundary = "no-reverse";
              };
              deniedPaths = [
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "living-room-cast"; }; reason = "guest-to-media-denied"; negativeProbe = "guest-to-cast"; }
                { kind = "media-to-management"; from = { kind = "tenant"; name = "media"; }; to = { kind = "management"; name = "living-room-cast"; }; reason = "media-to-management-denied"; negativeProbe = "media-to-management"; }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "receiver-pairing";
              cloudDependency = "optional";
            };
          }
        ];
        relations = [
          {
            id = "allow-media-to-receiver";
            priority = 100;
            from = { kind = "tenant"; name = "media"; };
            to = { kind = "service"; name = "living-room-cast"; };
            trafficType = "cast";
            action = "allow";
          }
          {
            id = "allow-media-to-wan";
            priority = 200;
            from = { kind = "tenant"; name = "media"; };
            to = { kind = "external"; uplinks = [ "wan" ]; };
            trafficType = "cast";
            action = "allow";
          }
        ];
      };
      topology.nodes = {
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
        [ "access-media" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
MO3

nix run "$ROOT#compile" -- "$media_dp_good_input" >"${tmp_dir}/media-dp-good-out.json" 2>/dev/null
jq -e '
  .sites.esp0xdeadbeef."site-a".services[0].deniedPaths[0].reason == "guest-to-media-denied"
' "${tmp_dir}/media-dp-good-out.json" >/dev/null

echo "PASS FS-640-HDS-010-SDS-010-SMS-050: media denied-path preservation OK (SN1 MEDIA_DENIED_PATH_MISSING, SN2 MEDIA_DENIED_PATH_OVERWRITTEN, POSITIVE)"
