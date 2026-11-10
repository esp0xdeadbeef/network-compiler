#!/usr/bin/env bash
# GAMP-ID: FS-482-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-482-HDS-010-SDS-010-SMS-030.md
# OWNER:  network-compiler
# MODULE: Learned-Route Classification  (lib/stages/learned-route-classification.nix)
#
# Behavioural case against the real module. Not executed before commit.
#
# Predicates taken from the SMS:
#   P1  A BGP-learned route is classified as conditional route availability.
#   P2  A learned route is kept out of the owned-prefix surface.
#   P3  A learned route is kept out of the payload-permission surface.
#   P4  Each learned route carries peer, address family and import
#       classification.
#
# Seeded negatives the SMS requires:
#   SN1  A learned route presented as an owned prefix is refused
#        (`E_LEARNED_ROUTE_OWNED_PREFIX_CONFLICT`).
#   SN2  A learned route with no import classification is refused
#        (`E_LEARNED_ROUTE_IMPORT_UNCLASSIFIED`).
#   SN3  A learned route missing peer or family is refused
#        (`E_LEARNED_ROUTE_IDENTITY_MISSING`).
#   SN4  A complete learned route is classified conditional and owned=false.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL learned-route-classification: $*" >&2; exit 1; }

mod_expr() {
  nix eval --no-write-lock-file --impure --json --expr '
    let
      f = builtins.getFlake "'"path:${repo_root}"'";
      pkgs = import f.inputs.nixpkgs { };
      mod = import "'"${repo_root}"'/lib/stages/learned-route-classification.nix" { lib = pkgs.lib; };
    in
      '"$1"''
}

# SN4/P1/P2/P3: a complete learned route is conditional, not owned, and does not
# reach either forbidden surface.
out="$(mod_expr '
  let
    r = mod.build {
      key = "site-a";
      ownership = { };
      learnedRoutes = [ {
        prefix = "203.0.113.0/24";
        peer = "203.0.113.1";
        family = "ipv4";
        importClassification = "conditional";
      } ];
    };
  in
    { route = builtins.head r.conditionalAvailability;
      owned = r.ownedPrefixSurface;
      perm = r.payloadPermissionSurface; }
' 2>&1)" || fail "P1 a complete learned route could not be classified
${out}"

jq -e '.route.availability == "conditional" and .route.owned == false and .route.payloadPermission == false' \
  >/dev/null 2>&1 <<<"${out}" || fail "P1/SN4 the learned route was not classified conditional and unowned: ${out}"
jq -e '.owned == [] and .perm == []' >/dev/null 2>&1 <<<"${out}" || \
  fail "P2/P3 a learned route reached the owned-prefix or payload-permission surface: ${out}"

# SN2: no import classification is refused.
set +e
out="$(mod_expr 'mod.build {
  key = "site-a";
  ownership = { };
  learnedRoutes = [ {
    prefix = "203.0.113.0/24"; peer = "203.0.113.1"; family = "ipv4";
  } ];
}' 2>&1)"
rc=$?
set -e
((rc != 0)) || fail "SN2 a learned route with no import classification was accepted"
grep -q 'E_LEARNED_ROUTE_IMPORT_UNCLASSIFIED' <<<"${out}" || fail "SN2 the refusal did not carry E_LEARNED_ROUTE_IMPORT_UNCLASSIFIED
${out}"

# SN3: a missing peer is refused, naming the identity fields.
set +e
out="$(mod_expr 'mod.build {
  key = "site-a";
  ownership = { };
  learnedRoutes = [ {
    prefix = "203.0.113.0/24"; family = "ipv4"; importClassification = "conditional";
  } ];
}' 2>&1)"
rc=$?
set -e
((rc != 0)) || fail "SN3 a learned route with no peer was accepted"
grep -q 'E_LEARNED_ROUTE_IDENTITY_MISSING' <<<"${out}" || fail "SN3 the refusal did not carry E_LEARNED_ROUTE_IDENTITY_MISSING
${out}"

echo "PASS learned-route-classification"
