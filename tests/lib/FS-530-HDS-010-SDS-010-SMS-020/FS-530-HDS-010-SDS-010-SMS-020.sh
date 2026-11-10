#!/usr/bin/env bash
# GAMP-ID: FS-530-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-530-HDS-010-SDS-010-SMS-020.md
# OWNER:  network-compiler
#
# Behavioural case: compile the real example, then remove the modeled DNS policy
# from one tenant prefix and require that the model never substitutes a domain.
#
# Predicates taken from the SMS:
#   P1  A missing DNS policy is rejected before canonical resolver advertisement is
#       accepted.
#   P2  The diagnostic names the missing DNS policy input.
#
# Seeded negatives:
#   SN1  Removing the modeled DNS domain from a tenant prefix produces either a
#        refusal naming the missing input, or a model with no domain for that
#        tenant. What must never happen is a silently defaulted domain.
#
# Not executed before commit.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"
system="${NIX_SYSTEM:-$(nix eval --no-write-lock-file --impure --raw --expr 'builtins.currentSystem')}"

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing required command: $1" >&2; exit 1; }
}

require_cmd jq

flake_input_path() {
  local input_name="$1"
  if [[ "${input_name}" == "network-labs" && -n "${NETWORK_LABS_PATH:-}" ]]; then
    realpath "${NETWORK_LABS_PATH}"; return
  fi
  nix flake archive --json "path:${repo_root}" | jq -er ".inputs[\"${input_name}\"].path"
}

labs_root="$(flake_input_path network-labs)"
example_root="${labs_root}/examples/single-wan"
intent_path="${example_root}/intent.nix"
inventory_path="${example_root}/inventory-nixos.nix"

tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT

# The compiler consumes the intent; the inventory is a renderer input and is not
# part of the compiled model. `compilePath` is the flake's real compile entry
# point, so the case compiles the intent through it.
compile_paths() {
  local intent="$1"
  nix eval --no-write-lock-file --impure --json --expr '
    let
      flake = builtins.getFlake "'"path:${repo_root}"'";
    in
      flake.libBySystem."'"${system}"'".compilePath "'"${intent}"'"
  '
}

fail() { echo "FAIL dns-policy-requirement: $*" >&2; exit 1; }

# Baseline: the example compiles and carries the modeled dnsDomain, so the
# negative below is attributable to its removal.
baseline_json="${tmp_dir}/baseline.json"
compile_paths "${intent_path}" >"${baseline_json}" \
  || fail "P1 the unmutated example does not compile, so no DNS-policy result can be attributed"

if ! grep -q '"dnsDomain":"lan\."' "${baseline_json}"; then
  fail "P1 the compiled baseline carries no modeled dnsDomain, so the modeled DNS policy is not reaching the model"
fi

# SN1: remove dnsDomain from the client tenant prefix.
no_dns_intent="${tmp_dir}/intent-no-dns-domain.nix"
cat >"${no_dns_intent}" <<EOF
let
  base = import ${intent_path};
  site = base.esp0xdeadbeef."site-a";
  stripDomain =
    prefix:
    if (prefix.name or null) == "client" then builtins.removeAttrs prefix [ "dnsDomain" ]
    else prefix;
in
base // {
  esp0xdeadbeef = base.esp0xdeadbeef // {
    "site-a" = site // {
      ownership = site.ownership // {
        prefixes = map stripDomain site.ownership.prefixes;
      };
    };
  };
}
EOF

set +e
compile_paths "${no_dns_intent}" >"${tmp_dir}/no-dns.out" 2>"${tmp_dir}/no-dns.err"
no_dns_rc=$?
set -e

if ((no_dns_rc != 0)); then
  # A refusal is conforming only if it names the missing DNS policy input.
  if ! grep -qiE 'dnsDomain|dns.?policy|domain' "${tmp_dir}/no-dns.err"; then
    fail "P2 the run refused but did not name the missing DNS policy input
$(cat "${tmp_dir}/no-dns.err")"
  fi
  echo "PASS dns-policy-requirement"
  exit 0
fi

# The run succeeded: it may omit the domain for that tenant, but it must not
# invent one. A defaulted domain for the client tenant is the defect.
# The defect is a domain the model *invented for the client tenant*. Read the
# tenant entry rather than the whole site: other tenants legitimately model their
# own dnsDomain, and a whole-site text match cannot distinguish them (and, using
# `builtins.match`, silently cannot span the JSON at all).
if ! NO_DNS_JSON="${tmp_dir}/no-dns.out" nix eval --no-write-lock-file --impure --expr '
  let
    d = builtins.fromJSON (builtins.readFile (builtins.getEnv "NO_DNS_JSON"));
    site = d.sites.esp0xdeadbeef."site-a";
    client = builtins.head (
      builtins.filter (t: (t.name or null) == "client") (site.tenants or [ ])
    );
  in
    # A surviving domain means one was defaulted rather than required.
    (client.dnsDomain or null) == null
' | grep -qx true; then
  fail "SN1 removing the modeled dnsDomain still produced a domain for the client tenant, so a DNS policy was defaulted rather than required"
fi

echo "PASS dns-policy-requirement"
