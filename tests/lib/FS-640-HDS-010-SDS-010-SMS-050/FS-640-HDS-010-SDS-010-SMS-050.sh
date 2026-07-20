#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-640-HDS-010-SDS-010-SMS-050
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# ---- Positive: media-receiver with proper guest denied-path ----
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
              management = { allowed = false; boundary = "no-management"; };
              reverseInitiation = { allowed = false; boundary = "no-reverse"; };
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
          { id = "allow-media-to-receiver"; priority = 100; from = { kind = "tenant"; name = "media"; }; to = { kind = "service"; name = "living-room-cast"; }; trafficType = "cast"; action = "allow"; }
          { id = "allow-media-to-wan"; priority = 200; from = { kind = "tenant"; name = "media"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "cast"; action = "allow"; }
        ];
      };
      topology.nodes = {
        access-media = { role = "access"; attachments = [ { kind = "tenant"; name = "media"; } ]; };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; };
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

echo "=== Positive: media-receiver with guest denied-path preserved ==="
nix run "$ROOT#compile" -- "$good_input" > "${tmp_dir}/good-out.json" 2>/dev/null
jq -e '
  .sites.esp0xdeadbeef."site-a".services[0].serviceClass == "media-receiver"
  and (.sites.esp0xdeadbeef."site-a".services[0].deniedPaths | length >= 1)
  and .sites.esp0xdeadbeef."site-a".services[0].deniedPaths[0].reason == "guest-to-media-denied"
' "${tmp_dir}/good-out.json" >/dev/null
echo "PASS: POSITIVE (guest denied-path preserved in output)"

# ---- SN1: guest-to-trusted denied path omitted → MEDIA_DENIED_PATH_MISSING ----
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
              management = { allowed = false; boundary = "no-management"; };
              reverseInitiation = { allowed = false; boundary = "no-reverse"; };
              deniedPaths = [
                { kind = "media-to-management"; from = { kind = "tenant"; name = "media"; }; to = { kind = "management"; name = "living-room-cast"; }; reason = "media-to-management-denied"; negativeProbe = "media-to-management"; }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "receiver-pairing";
              cloudDependency = "optional";
            };
          }
        ];
        relations = [
          { id = "allow-media-to-receiver"; priority = 100; from = { kind = "tenant"; name = "media"; }; to = { kind = "service"; name = "living-room-cast"; }; trafficType = "cast"; action = "allow"; }
          { id = "allow-media-to-wan"; priority = 200; from = { kind = "tenant"; name = "media"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "cast"; action = "allow"; }
        ];
      };
      topology.nodes = {
        access-media = { role = "access"; attachments = [ { kind = "tenant"; name = "media"; } ]; };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; };
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
SN1

set +e
nix run "$ROOT#compile" -- "$sn1_input" 2>"${tmp_dir}/sn1.err" >/dev/null
sn1_rc=$?
set -e
if [[ "$sn1_rc" -eq 0 ]]; then
  echo "FAIL SN1: media-receiver without guest denied-path compiled successfully" >&2
  exit 1
fi
grep -q "MEDIA_DENIED_PATH_MISSING" "${tmp_dir}/sn1.err"
echo "PASS SN1: MEDIA_DENIED_PATH_MISSING"

# ---- SN2: clearDeniedPaths flag set — expect MEDIA_DENIED_PATH_OVERWRITTEN ----
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
              management = { allowed = false; boundary = "no-management"; };
              reverseInitiation = { allowed = false; boundary = "no-reverse"; };
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
          { id = "allow-media-to-receiver"; priority = 100; from = { kind = "tenant"; name = "media"; }; to = { kind = "service"; name = "living-room-cast"; }; trafficType = "cast"; action = "allow"; }
          { id = "allow-media-to-wan"; priority = 200; from = { kind = "tenant"; name = "media"; }; to = { kind = "external"; uplinks = [ "wan" ]; }; trafficType = "cast"; action = "allow"; }
        ];
      };
      topology.nodes = {
        access-media = { role = "access"; attachments = [ { kind = "tenant"; name = "media"; } ]; };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core = { role = "core"; uplinks.wan.ipv4 = [ "0.0.0.0/0" ]; };
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
SN2

set +e
nix run "$ROOT#compile" -- "$sn2_input" 2>"${tmp_dir}/sn2.err" >/dev/null
sn2_rc=$?
set -e
if [[ "$sn2_rc" -eq 0 ]]; then
  echo "FAIL SN2: media-receiver with clearDeniedPaths=true compiled successfully" >&2
  exit 1
fi
grep -q "MEDIA_DENIED_PATH_OVERWRITTEN" "${tmp_dir}/sn2.err"
echo "PASS SN2: MEDIA_DENIED_PATH_OVERWRITTEN"

echo "=== All FS-640-HDS-010-SDS-010-SMS-050 tests PASSED ==="
