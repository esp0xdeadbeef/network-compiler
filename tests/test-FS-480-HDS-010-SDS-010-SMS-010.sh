#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: FS-480-HDS-010-SDS-010-SMS-010
# GAMP-SCOPE: software-module-test

ROOT="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

input_nix="${tmp_dir}/fs480-route-import-authority-passthrough.nix"
output_json="${tmp_dir}/fs480-route-import-authority-passthrough.json"

cat >"$input_nix" <<EOF
let
  base = import ${ROOT}/tests/fixtures/single-uplink.nix;
  site = base.esp0xdeadbeef."site-a";
in
base
// {
  esp0xdeadbeef =
    base.esp0xdeadbeef
    // {
      "site-a" =
        site
        // {
          prefixAuthority = {
            routeImportConstraints = [
              {
                id = "explicit-runtime-route-import";
                gampId = "FS-480-HDS-010-SDS-010-SMS-010";
                authorityId = "prefix-authority::s-router-access::4|198.51.100.48/32";
                routePrefix = "198.51.100.48/32";
                allowedPrefixes = [ "198.51.100.48/32" ];
                sourcePeerOrProvider = "uplink0";
                allowedSources = [ "uplink0" ];
                routePurpose = "owned-public-service-prefix";
                allowedPurposes = [ "owned-public-service-prefix" ];
                destinationOwner = "s-router-access";
                allowedDestinationOwners = [ "s-router-access" ];
                maximumScope = "site";
                routeScope = "site";
                exportRequested = true;
                exportEligible = true;
                rejectionBehavior = "reject";
              }
              {
                id = "missing-authority-runtime-route";
                gampId = "FS-480-HDS-010-SDS-010-SMS-040";
                authorityId = "prefix-authority::missing::4|203.0.113.48/32";
                routePrefix = "203.0.113.48/32";
                allowedPrefixes = [ "203.0.113.48/32" ];
                sourcePeerOrProvider = "uplink0";
                allowedSources = [ "uplink0" ];
                routePurpose = "provider-prefix";
                allowedPurposes = [ "provider-prefix" ];
                destinationOwner = "provider-uplink0";
                allowedDestinationOwners = [ "provider-uplink0" ];
                maximumScope = "provider";
                routeScope = "provider";
                exportRequested = false;
                exportEligible = false;
                rejectionBehavior = "reject";
              }
            ];
          };
        };
    };
}
EOF

nix run "$ROOT#compile" -- "$input_nix" > "$output_json"

jq -e '
  .sites.esp0xdeadbeef."site-a" as $site
  | $site.prefixAuthority.routeImportConstraints as $constraints
  | ($constraints | length == 2)
    and ($constraints[0].id == "explicit-runtime-route-import")
    and ($constraints[0].gampId == "FS-480-HDS-010-SDS-010-SMS-010")
    and ($constraints[0].sourcePeerOrProvider == "uplink0")
    and ($constraints[0].routePurpose == "owned-public-service-prefix")
    and ($constraints[0].maximumScope == "site")
    and ($constraints[0].rejectionBehavior == "reject")
    and ($constraints[1].id == "missing-authority-runtime-route")
    and ($constraints[1].gampId == "FS-480-HDS-010-SDS-010-SMS-040")
    and ($constraints[1].authorityId == "prefix-authority::missing::4|203.0.113.48/32")
    and ($constraints[1].routePurpose == "provider-prefix")
    and ([
      $site.sourceAudit.behavior[]
      | select(
          .outputPath == ["prefixAuthority"]
          and .sourcePath == ["prefixAuthority"]
          and .sourceClass == "user-intent"
          and .authority == "network-compiler"
        )
    ] | length == 1)
' "$output_json" >/dev/null || {
  echo "FAIL FS-480 route-import authority pass-through: compiler dropped prefixAuthority routeImportConstraints" >&2
  jq '.sites.esp0xdeadbeef."site-a" | {prefixAuthority, sourceAudit}' "$output_json" >&2
  exit 1
}

echo "PASS FS-480 route-import authority pass-through"
