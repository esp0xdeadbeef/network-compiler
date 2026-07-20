#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-270-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

input_nix="${tmp_dir}/fs270-sms020-client-tenant-policy-transit.nix"
output_json="${tmp_dir}/fs270-sms020-client-tenant-policy-transit.json"

cat >"$input_nix" <<'NIX'
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
          { kind = "tenant"; name = "dmz"; ipv4 = "10.20.30.0/24"; }
        ];
        endpoints = [
          { kind = "host"; name = "dmz-api"; tenant = "dmz"; }
        ];
      };

      communicationContract = {
        trafficTypes = [ ];
        services = [
          { name = "dmz-api"; providers = [ "dmz-api" ]; trafficType = "any"; }
        ];
        relations = [
          {
            id = "allow-client-to-dmz-api";
            priority = 120;
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "service"; name = "dmz-api"; };
            trafficType = "any";
            action = "allow";
          }
          {
            id = "allow-client-to-wan";
            priority = 130;
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "external"; uplinks = [ "wan0" ]; };
            trafficType = "any";
            action = "allow";
          }
        ];
      };

      topology.nodes = {
        access-client = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
          placement.sharedHost = "transit-host";
          hostLocal.management = true;
        };
        access-dmz = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "dmz"; } ];
        };
        downstream = {
          role = "downstream-selector";
          routeAvailability.default = true;
        };
        policy = {
          role = "policy";
          placement.sharedHost = "transit-host";
          providerProfile = "tempting-provider";
        };
        upstream = {
          role = "upstream-selector";
          routeAvailability.default = true;
        };
        core = {
          role = "core";
          placement.sharedHost = "transit-host";
          providerProfile = "tempting-provider";
          routeAvailability.default = true;
          uplinks.wan0.ipv4 = [ "0.0.0.0/0" ];
        };
      };

      topology.links = [
        [ "access-client" "downstream" ]
        [ "access-dmz" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
NIX

nix run "$ROOT#compile" -- "$input_nix" >"$output_json"

jq -e '
  def path($id):
    [.sites.esp0xdeadbeef."site-a".trafficPaths[] | select(.relationId == $id)];
  def has_path($id; $stagePath; $nodePath):
    (path($id) | length == 1)
    and (path($id)[0].stagePath == $stagePath)
    and (path($id)[0].nodePath == $nodePath)
    and (path($id)[0].requiresPolicy == true)
    and (path($id)[0].forbidsCoreToCoreP2P == true)
    and (path($id)[0].p2pIsolationKey == $id);

  has_path(
    "allow-client-to-dmz-api";
    ["access", "downstream-selector", "policy", "downstream-selector", "access"];
    ["access-client", "downstream", "policy", "downstream", "access-dmz"]
  )
' "$output_json" >/dev/null

echo "PASS FS-270-HDS-010-SDS-010-SMS-020"
