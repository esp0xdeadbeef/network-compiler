#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-180-HDS-010-SDS-010-SMS-020
# GAMP-ID: SMT-COMP-FS180-ADJACENT-DENIAL-001
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

input_file="${tmp_dir}/adjacent-traffic-denial.nix"
output_json="${tmp_dir}/adjacent-traffic-denial.json"

cat >"$input_file" <<'NIX'
{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p.ipv4 = "10.10.0.0/24";
        loopback.ipv4 = "10.19.0.0/24";
      };

      ownership = {
        prefixes = [
          { kind = "tenant"; name = "client"; ipv4 = "10.20.10.0/24"; }
          { kind = "tenant"; name = "admin"; ipv4 = "10.20.20.0/24"; }
          { kind = "tenant"; name = "dmz"; ipv4 = "10.20.30.0/24"; }
        ];
        endpoints = [
          { kind = "host"; name = "admin-web-host"; tenant = "admin"; }
          { kind = "host"; name = "dmz-web-host"; tenant = "dmz"; }
        ];
      };

      communicationContract = {
        trafficTypes = [
          { name = "https"; match = [ { proto = "tcp"; family = "any"; dports = [ 443 ]; } ]; }
          { name = "ssh"; match = [ { proto = "tcp"; family = "any"; dports = [ 22 ]; } ]; }
        ];
        services = [
          { name = "admin-web"; providers = [ "admin-web-host" ]; trafficType = "https"; }
          { name = "dmz-web"; providers = [ "dmz-web-host" ]; trafficType = "https"; }
        ];
        relations = [
          {
            id = "allow-client-to-admin-web-https";
            priority = 10;
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "service"; name = "admin-web"; };
            trafficType = "https";
            action = "allow";
          }
          {
            id = "deny-client-to-admin-web-ssh";
            priority = 20;
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "service"; name = "admin-web"; };
            trafficType = "ssh";
            action = "deny";
          }
          {
            id = "deny-admin-to-admin-web-https";
            priority = 30;
            from = { kind = "tenant"; name = "admin"; };
            to = { kind = "service"; name = "admin-web"; };
            trafficType = "https";
            action = "deny";
          }
          {
            id = "deny-client-to-dmz-web-https";
            priority = 40;
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "service"; name = "dmz-web"; };
            trafficType = "https";
            action = "deny";
          }
          {
            id = "allow-client-to-wan";
            priority = 50;
            from = { kind = "tenant"; name = "client"; };
            to = { kind = "external"; uplinks = [ "wan" ]; };
            trafficType = "https";
            action = "allow";
          }
        ];
      };

      topology.nodes = {
        access-client = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "client"; } ];
        };
        access-admin = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "admin"; } ];
        };
        access-dmz = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "dmz"; } ];
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
        [ "access-admin" "downstream" ]
        [ "access-dmz" "downstream" ]
        [ "downstream" "policy" ]
        [ "policy" "upstream" ]
        [ "upstream" "core" ]
      ];
    };
  };
}
NIX

nix run "$ROOT#compile" -- "$input_file" >"$output_json"

jq -e '
  .sites.esp0xdeadbeef."site-a" as $site
  | ([
      $site.relations[]
      | select(.action == "allow")
      | .source.id
    ] | sort) == [
      "allow-client-to-admin-web-https",
      "allow-client-to-wan"
    ]
  and ([
      $site.relations[]
      | select(.action == "deny")
      | .source.id
    ] | sort) == [
      "deny-admin-to-admin-web-https",
      "deny-client-to-admin-web-ssh",
      "deny-client-to-dmz-web-https"
    ]
  and ([
      $site.trafficPaths[]
      | select(.relationId == "allow-client-to-admin-web-https")
      | select(.action == "allow")
      | select(.trafficType == "https")
      | select(.destination.kind == "service" and .destination.name == "admin-web")
      | select(.nodePath == [
          "access-client",
          "downstream",
          "policy",
          "downstream",
          "access-admin"
        ])
    ] | length) == 1
  and ([
      $site.trafficPaths[]
      | select(.relationId == "deny-client-to-admin-web-ssh")
      | select(.action == "deny")
      | select(.trafficType == "ssh")
      | select(.destination.kind == "service" and .destination.name == "admin-web")
      | select(.nodePath[-1] == "access-admin")
    ] | length) == 1
  and ([
      $site.trafficPaths[]
      | select(.relationId == "deny-admin-to-admin-web-https")
      | select(.action == "deny")
      | select(.source.kind == "tenant" and .source.name == "admin")
      | select(.destination.kind == "service" and .destination.name == "admin-web")
    ] | length) == 1
  and ([
      $site.trafficPaths[]
      | select(.relationId == "deny-client-to-dmz-web-https")
      | select(.action == "deny")
      | select(.source.kind == "tenant" and .source.name == "client")
      | select(.destination.kind == "service" and .destination.name == "dmz-web")
      | select(.nodePath[-1] == "access-dmz")
    ] | length) == 1
  and all(
      $site.trafficPaths[]
      | select(.relationId | startswith("deny-"));
      .action == "deny"
    )
' "$output_json" >/dev/null

echo "PASS adjacent-traffic-denial"
