#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-630-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
# Focused construction test for printer payload authorization module.
# Seeded negatives:
#   SN1 (MISSING_PAYLOAD_DIRECTION): printer payload with protocol+ports but no direction
#   SN2 (PAYLOAD_AUTHORIZATION_INFERRED_FROM_DISCOVERY): printer has discovery but no payload

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

# ---------------------------------------------------------------------------
# POSITIVE: well-formed printer service compiles and emits all fields
# ---------------------------------------------------------------------------
positive_input="${tmp_dir}/positive.nix"

cat >"$positive_input" <<'NIX'
{
  esp0xcafe = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.99.0.0/24";
        loopback.ipv4 = "10.99.1.0/24";
      };
      ownership = {
        prefixes = [
          { kind = "tenant"; name = "trusted"; ipv4 = "10.99.10.0/24"; }
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
            name = "office-printer-1";
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
              management = { allowed = false; boundary = "admin-scope-only"; };
              reverseInitiation = { allowed = false; boundary = "no-printer-initiated-paths"; };
              deniedPaths = [
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "office-printer-1"; }; reason = "guest-print-denied"; negativeProbe = "guest-to-printer-ipp"; }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "printer-local";
              cloudDependency = "none";
            };
          }
        ];
        relations = [
          {
            id = "allow-trusted-to-printer";
            priority = 100;
            from = { kind = "tenant"; name = "trusted"; };
            to = { kind = "service"; name = "office-printer-1"; };
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

echo "=== POSITIVE: well-formed printer service ==="
nix run "$ROOT#compile" -- "$positive_input" >"${tmp_dir}/positive.json"

jq -e '
  .sites.esp0xcafe."site-a".services as $svcs
  | ($svcs | length == 1)
  and (
    $svcs[0].name == "office-printer-1"
    and $svcs[0].serviceClass == "printer"
    and $svcs[0].payload.protocol == "ipp"
    and $svcs[0].payload.ports == [631]
    and $svcs[0].payload.direction == "requester-to-responder"
    and $svcs[0].payload.returnBehavior == "established-only"
    and $svcs[0].exposureClass == "internal-shared"
  )
' "${tmp_dir}/positive.json" >/dev/null
echo "PASS POSITIVE: printer service compiled with complete payload fields"

# ---------------------------------------------------------------------------
# SN1: Printer payload with protocol+ports but MISSING direction → MISSING_PAYLOAD_DIRECTION
# ---------------------------------------------------------------------------
sn1_input="${tmp_dir}/sn1-missing-direction.nix"

cat >"$sn1_input" <<'NIX'
{
  esp0xcafe = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.99.0.0/24";
        loopback.ipv4 = "10.99.1.0/24";
      };
      ownership = {
        prefixes = [
          { kind = "tenant"; name = "trusted"; ipv4 = "10.99.10.0/24"; }
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
            name = "office-printer-1";
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
                protocol = "tcp";
                ports = [ 631 ];
              };
              management = { allowed = false; boundary = "admin-scope-only"; };
              reverseInitiation = { allowed = false; boundary = "no-printer-initiated-paths"; };
              deniedPaths = [
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "office-printer-1"; }; reason = "guest-print-denied"; negativeProbe = "guest-to-printer-ipp"; }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "printer-local";
              cloudDependency = "none";
            };
          }
        ];
        relations = [
          {
            id = "allow-trusted-to-printer";
            priority = 100;
            from = { kind = "tenant"; name = "trusted"; };
            to = { kind = "service"; name = "office-printer-1"; };
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

echo "=== SN1: printer payload missing direction ==="
set +e
nix run "$ROOT#compile" -- "$sn1_input" 2>"${tmp_dir}/sn1.err" >/dev/null
sn1_rc=$?
set -e
if [[ "$sn1_rc" -eq 0 ]]; then
  echo "FAIL SN1: printer compiled with missing direction" >&2
  exit 1
fi
if ! grep -q "MISSING_PAYLOAD_DIRECTION" "${tmp_dir}/sn1.err"; then
  echo "FAIL SN1: expected MISSING_PAYLOAD_DIRECTION diagnostic not found" >&2
  cat "${tmp_dir}/sn1.err" >&2
  exit 1
fi
echo "PASS SN1: MISSING_PAYLOAD_DIRECTION diagnostic emitted"

# ---------------------------------------------------------------------------
# SN2: Printer has discovery but no payload → PAYLOAD_AUTHORIZATION_INFERRED_FROM_DISCOVERY
# ---------------------------------------------------------------------------
sn2_input="${tmp_dir}/sn2-discovery-no-payload.nix"

cat >"$sn2_input" <<'NIX'
{
  esp0xcafe = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.99.0.0/24";
        loopback.ipv4 = "10.99.1.0/24";
      };
      ownership = {
        prefixes = [
          { kind = "tenant"; name = "trusted"; ipv4 = "10.99.10.0/24"; }
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
            name = "office-printer-1";
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
              management = { allowed = false; boundary = "admin-scope-only"; };
              reverseInitiation = { allowed = false; boundary = "no-printer-initiated-paths"; };
              deniedPaths = [
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "office-printer-1"; }; reason = "guest-print-denied"; negativeProbe = "guest-to-printer-ipp"; }
              ];
              exposureClass = "internal-shared";
              authenticationBoundary = "printer-local";
              cloudDependency = "none";
            };
          }
        ];
        relations = [
          {
            id = "allow-trusted-to-printer";
            priority = 100;
            from = { kind = "tenant"; name = "trusted"; };
            to = { kind = "service"; name = "office-printer-1"; };
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

echo "=== SN2: printer discovery present but no payload ==="
set +e
nix run "$ROOT#compile" -- "$sn2_input" 2>"${tmp_dir}/sn2.err" >/dev/null
sn2_rc=$?
set -e
if [[ "$sn2_rc" -eq 0 ]]; then
  echo "FAIL SN2: printer compiled with no payload" >&2
  exit 1
fi
if ! grep -q "PAYLOAD_AUTHORIZATION_INFERRED_FROM_DISCOVERY" "${tmp_dir}/sn2.err"; then
  echo "FAIL SN2: expected PAYLOAD_AUTHORIZATION_INFERRED_FROM_DISCOVERY diagnostic not found" >&2
  cat "${tmp_dir}/sn2.err" >&2
  exit 1
fi
echo "PASS SN2: PAYLOAD_AUTHORIZATION_INFERRED_FROM_DISCOVERY diagnostic emitted"

# ---------------------------------------------------------------------------
# Verify non-printer services are NOT affected (regression check)
# ---------------------------------------------------------------------------
echo "=== REGRESSION: non-printer service (serviceClass != printer) not affected ==="

non_printer_input="${tmp_dir}/non-printer.nix"

cat >"$non_printer_input" <<'NIX'
{
  esp0xcafe = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.99.0.0/24";
        loopback.ipv4 = "10.99.1.0/24";
      };
      ownership = {
        prefixes = [
          { kind = "tenant"; name = "trusted"; ipv4 = "10.99.10.0/24"; }
        ];
        endpoints = [
          { kind = "host"; name = "svc01"; tenant = "trusted"; }
        ];
      };
      communicationContract = {
        trafficTypes = [
          { name = "dns"; match = [ { proto = "udp"; family = "any"; dports = [ 53 ]; } ]; }
        ];
        services = [
          {
            name = "dns-resolver";
            providers = [ "svc01" ];
            trafficType = "dns";
            servicePolicy = {
              requesterScopes = [ { kind = "tenant"; name = "trusted"; } ];
              responderScope = { kind = "host"; name = "svc01"; tenant = "trusted"; };
              serviceClass = "dns";
              discovery = {
                protocol = "mdns";
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
                { from = { kind = "tenant"; name = "guest"; }; to = { kind = "service"; name = "dns-resolver"; }; reason = "guest-resolver-denied"; negativeProbe = "guest-to-resolver-dns"; }
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
            to = { kind = "service"; name = "dns-resolver"; };
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
nix run "$ROOT#compile" -- "$non_printer_input" >"${tmp_dir}/non-printer.json" 2>"${tmp_dir}/non-printer.err"
non_printer_rc=$?
set -e
if [[ "$non_printer_rc" -ne 0 ]]; then
  echo "FAIL REGRESSION: non-printer service failed to compile" >&2
  cat "${tmp_dir}/non-printer.err" >&2
  exit 1
fi
echo "PASS REGRESSION: non-printer service compiles without interference"

echo ""
echo "=== FS-630-HDS-010-SDS-010-SMS-020 ALL TESTS PASSED ==="
echo "RESULTS: POSITIVE + SN1 (MISSING_PAYLOAD_DIRECTION) + SN2 (PAYLOAD_AUTHORIZATION_INFERRED_FROM_DISCOVERY) + REGRESSION"
