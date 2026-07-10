#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-640-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# ---- Positive: media-receiver with complete payload tuple ----
good_input="${tmp_dir}/media-good.nix"
cat >"$good_input" <<'NIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = { p2p.ipv4 = "10.10.0.0/24"; loopback.ipv4 = "10.19.0.0/24"; };
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
          { name = "cast"; match = [ { proto = "tcp"; family = "any"; dports = [ 8009 ]; } ]; }
        ];
        services = [
          {
            name = "living-room-cast";
            providers = [ "living-room-cast" ];
            trafficType = "cast";
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "trusted"; } ];
              responderScope = { kind = "host"; name = "living-room-cast"; tenant = "media"; };
              serviceClass = "media-receiver";
              discovery = {
                protocol = "mdns";
                direction = "responder-to-controller";
                advertisedServices = [ "_cast._tcp" ];
              };
              payload = {
                protocol = "tcp";
                ports = [ 8009 ];
                direction = "controller-to-receiver";
                returnBehavior = "established-only";
              };
              management = { allowed = false; boundary = "receiver-management-denied"; };
              reverseInitiation = { allowed = false; boundary = "no-receiver-initiated-controller-paths"; };
              deniedPaths = [
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "living-room-cast"; }; reason = "guest-cast-denied"; negativeProbe = "guest-to-cast"; }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "receiver-pairing";
              cloudDependency = "optional";
            };
          }
        ];
        relations = [
          { id = "allow-trusted-to-cast"; priority = 100; from = { kind = "tenant"; name = "trusted"; }; to = { kind = "service"; name = "living-room-cast"; }; trafficType = "cast"; action = "allow"; }
          { id = "allow-trusted-to-wan"; priority = 200; from = { kind = "tenant"; name = "trusted"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "cast"; action = "allow"; }
        ];
      };
      topology.nodes = {
        access-media = { role = "access"; attachments = [ { kind = "tenant"; name = "media"; } ]; };
        access-trusted = { role = "access"; attachments = [ { kind = "tenant"; name = "trusted"; } ]; };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; };
      };
      topology.links = [
        [ "access-media" "downstream" ]
        [ "access-trusted" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
NIX

echo "=== Positive: media-receiver with complete payload tuple ==="
nix run "$ROOT#compile" -- "$good_input" > "${tmp_dir}/good-out.json" 2>/dev/null
jq -e '
  .sites.esp0xdeadbeef."site-a".services[0].payload.protocol == "tcp"
  and .sites.esp0xdeadbeef."site-a".services[0].payload.ports == [8009]
  and .sites.esp0xdeadbeef."site-a".services[0].cloudDependency == "optional"
' "${tmp_dir}/good-out.json" >/dev/null
echo "PASS: POSITIVE (media-receiver with complete payload tuple)"

# ---- SN1: media service with discovery but no payload → MEDIA_PAYLOAD_INFERRED_FROM_DISCOVERY ----
sn1_input="${tmp_dir}/media-sn1.nix"
cat >"$sn1_input" <<'SN1'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = { p2p.ipv4 = "10.10.0.0/24"; loopback.ipv4 = "10.19.0.0/24"; };
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
          { name = "cast"; match = [ { proto = "tcp"; family = "any"; dports = [ 8009 ]; } ]; }
        ];
        services = [
          {
            name = "living-room-cast";
            providers = [ "living-room-cast" ];
            trafficType = "cast";
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "trusted"; } ];
              responderScope = { kind = "host"; name = "living-room-cast"; tenant = "media"; };
              serviceClass = "media-receiver";
              discovery = {
                protocol = "mdns";
                direction = "responder-to-controller";
                advertisedServices = [ "_cast._tcp" ];
              };
              management = { allowed = false; boundary = "receiver-management-denied"; };
              reverseInitiation = { allowed = false; boundary = "no-receiver-initiated-controller-paths"; };
              deniedPaths = [
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "living-room-cast"; }; reason = "guest-cast-denied"; negativeProbe = "guest-to-cast"; }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "receiver-pairing";
              cloudDependency = "optional";
            };
          }
        ];
        relations = [
          { id = "allow-trusted-to-cast"; priority = 100; from = { kind = "tenant"; name = "trusted"; }; to = { kind = "service"; name = "living-room-cast"; }; trafficType = "cast"; action = "allow"; }
          { id = "allow-trusted-to-wan"; priority = 200; from = { kind = "tenant"; name = "trusted"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "cast"; action = "allow"; }
        ];
      };
      topology.nodes = {
        access-media = { role = "access"; attachments = [ { kind = "tenant"; name = "media"; } ]; };
        access-trusted = { role = "access"; attachments = [ { kind = "tenant"; name = "trusted"; } ]; };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; };
      };
      topology.links = [
        [ "access-media" "downstream" ]
        [ "access-trusted" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
SN1

set +e
nix run "$ROOT#compile" -- "$sn1_input" 2>"${tmp_dir}/sn1.err" >/dev/null
sn1_rc=$?
set -e
if [[ "$sn1_rc" -eq 0 ]]; then
  echo "FAIL SN1: media service with discovery but no payload compiled successfully" >&2
  exit 1
fi
grep -q "MEDIA_PAYLOAD_INFERRED_FROM_DISCOVERY" "${tmp_dir}/sn1.err"
echo "PASS SN1: MEDIA_PAYLOAD_INFERRED_FROM_DISCOVERY"

# ---- SN2: incomplete payload tuple → MEDIA_PAYLOAD_TUPLE_INCOMPLETE ----
# Media payload with tcp and port 8009 but cloudDependency and returnBehavior omitted
sn2_input="${tmp_dir}/media-sn2.nix"
cat >"$sn2_input" <<'SN2'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = { p2p.ipv4 = "10.10.0.0/24"; loopback.ipv4 = "10.19.0.0/24"; };
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
          { name = "cast"; match = [ { proto = "tcp"; family = "any"; dports = [ 8009 ]; } ]; }
        ];
        services = [
          {
            name = "living-room-cast";
            providers = [ "living-room-cast" ];
            trafficType = "cast";
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "trusted"; } ];
              responderScope = { kind = "host"; name = "living-room-cast"; tenant = "media"; };
              serviceClass = "media-receiver";
              discovery = {
                protocol = "mdns";
                direction = "responder-to-controller";
                advertisedServices = [ "_cast._tcp" ];
              };
              payload = {
                protocol = "tcp";
                ports = [ 8009 ];
                direction = "controller-to-receiver";
              };
              management = { allowed = false; boundary = "receiver-management-denied"; };
              reverseInitiation = { allowed = false; boundary = "no-receiver-initiated-controller-paths"; };
              deniedPaths = [
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "living-room-cast"; }; reason = "guest-cast-denied"; negativeProbe = "guest-to-cast"; }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "receiver-pairing";
            };
          }
        ];
        relations = [
          { id = "allow-trusted-to-cast"; priority = 100; from = { kind = "tenant"; name = "trusted"; }; to = { kind = "service"; name = "living-room-cast"; }; trafficType = "cast"; action = "allow"; }
          { id = "allow-trusted-to-wan"; priority = 200; from = { kind = "tenant"; name = "trusted"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "cast"; action = "allow"; }
        ];
      };
      topology.nodes = {
        access-media = { role = "access"; attachments = [ { kind = "tenant"; name = "media"; } ]; };
        access-trusted = { role = "access"; attachments = [ { kind = "tenant"; name = "trusted"; } ]; };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; };
      };
      topology.links = [
        [ "access-media" "downstream" ]
        [ "access-trusted" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
SN2

set +e
nix run "$ROOT#compile" -- "$sn2_input" 2>"${tmp_dir}/sn2.err" >/dev/null
sn2_rc=$?
set -e
if [[ "$sn2_rc" -eq 0 ]]; then
  echo "FAIL SN2: incomplete media payload tuple compiled successfully" >&2
  exit 1
fi
grep -q "MEDIA_PAYLOAD_TUPLE_INCOMPLETE" "${tmp_dir}/sn2.err"
echo "PASS SN2: MEDIA_PAYLOAD_TUPLE_INCOMPLETE"

# ---- SN2 positive follow-up: adding cloudDependency and returnBehavior makes it acceptable ----
sn2_positive_input="${tmp_dir}/media-sn2-positive.nix"
cat >"$sn2_positive_input" <<'SN2P'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = { p2p.ipv4 = "10.10.0.0/24"; loopback.ipv4 = "10.19.0.0/24"; };
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
          { name = "cast"; match = [ { proto = "tcp"; family = "any"; dports = [ 8009 ]; } ]; }
        ];
        services = [
          {
            name = "living-room-cast";
            providers = [ "living-room-cast" ];
            trafficType = "cast";
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "trusted"; } ];
              responderScope = { kind = "host"; name = "living-room-cast"; tenant = "media"; };
              serviceClass = "media-receiver";
              discovery = {
                protocol = "mdns";
                direction = "responder-to-controller";
                advertisedServices = [ "_cast._tcp" ];
              };
              payload = {
                protocol = "tcp";
                ports = [ 8009 ];
                direction = "controller-to-receiver";
                returnBehavior = "established-only";
              };
              management = { allowed = false; boundary = "receiver-management-denied"; };
              reverseInitiation = { allowed = false; boundary = "no-receiver-initiated-controller-paths"; };
              deniedPaths = [
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "living-room-cast"; }; reason = "guest-cast-denied"; negativeProbe = "guest-to-cast"; }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "receiver-pairing";
              cloudDependency = "optional";
            };
          }
        ];
        relations = [
          { id = "allow-trusted-to-cast"; priority = 100; from = { kind = "tenant"; name = "trusted"; }; to = { kind = "service"; name = "living-room-cast"; }; trafficType = "cast"; action = "allow"; }
          { id = "allow-trusted-to-wan"; priority = 200; from = { kind = "tenant"; name = "trusted"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "cast"; action = "allow"; }
        ];
      };
      topology.nodes = {
        access-media = { role = "access"; attachments = [ { kind = "tenant"; name = "media"; } ]; };
        access-trusted = { role = "access"; attachments = [ { kind = "tenant"; name = "trusted"; } ]; };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; };
      };
      topology.links = [
        [ "access-media" "downstream" ]
        [ "access-trusted" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
SN2P

nix run "$ROOT#compile" -- "$sn2_positive_input" > "${tmp_dir}/sn2-positive-out.json" 2>/dev/null
jq -e '
  .sites.esp0xdeadbeef."site-a".services[0].payload.returnBehavior == "established-only"
  and .sites.esp0xdeadbeef."site-a".services[0].cloudDependency == "optional"
' "${tmp_dir}/sn2-positive-out.json" >/dev/null
echo "PASS SN2 positive: completed tuple accepted"

echo "=== All FS-640-HDS-010-SDS-010-SMS-020 tests PASSED ==="
