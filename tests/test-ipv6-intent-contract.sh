#!/usr/bin/env bash
set -euo pipefail
# GAMP-ID: SMT-COMP-IPV6-INTENT-001
# GAMP-SCOPE: software-module-test

root="${NETWORK_COMPILER_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"
tmp_input="$(mktemp)"
tmp_output="$(mktemp)"
trap 'rm -f "${tmp_input}" "${tmp_output}"' EXIT

cat >"${tmp_input}" <<EOF
let
  base = import ${root}/tests/fixtures/single-uplink.nix;
in
{
  esp0xdeadbeef = {
    "site-a" = base.esp0xdeadbeef."site-a" // {
      ipv6 = {
        pd = {
          delegatedPrefixLength = 56;
          perTenantPrefixLength = 64;
          uplink = "uplink0";
        };
        tenants = {
          mgmt.mode = "slaac";
          admin.mode = "dhcpv6";
        };
      };
    };
  };
}
EOF

nix run "${root}#compile" -- "${tmp_input}" >"${tmp_output}"

jq -e '
  .sites.esp0xdeadbeef."site-a".ipv6.pd.delegatedPrefixLength == 56
  and .sites.esp0xdeadbeef."site-a".ipv6.pd.perTenantPrefixLength == 64
  and .sites.esp0xdeadbeef."site-a".ipv6.pd.uplink == "uplink0"
  and .sites.esp0xdeadbeef."site-a".ipv6.tenants.mgmt.mode == "slaac"
  and .sites.esp0xdeadbeef."site-a".ipv6.tenants.admin.mode == "dhcpv6"
' "${tmp_output}" >/dev/null || {
  echo "FAIL ipv6-intent-contract: compiler dropped site IPv6 PD intent" >&2
  jq '.sites.esp0xdeadbeef."site-a".ipv6' "${tmp_output}" >&2
  exit 1
}

echo "PASS ipv6-intent-contract"
