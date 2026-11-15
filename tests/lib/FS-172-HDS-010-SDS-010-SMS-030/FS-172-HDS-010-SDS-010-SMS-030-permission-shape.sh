#!/usr/bin/env bash
# GAMP-ID: FS-172-HDS-010-SDS-010-SMS-030
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-172-HDS-010-SDS-010-SMS-030.md
# OWNER:  network-compiler
# MODULE: Permission-Shape Restatement Refusal  (lib/derivation-registry/input-boundary.nix)
#
# Behavioural case against the real module. Covers the rule the registry names as
# DRV-SERVICE-PERMISSION-SHAPE ("network-compiler: relations"): a relation's
# traffic class is derived from the declaration of the service it targets, so a
# relation that restates that class duplicates the writer the rule owns.
#
# Predicates taken from the SMS:
#   P1  A source field that restates a fact a registry rule determines is refused
#       as a duplicate writer.
#   P2  The diagnostic carries all five required elements: the field, the
#       declaring scope, the determining declared fact, the rule identity, and
#       the derived value.
#   P3  The refusal is not a blanket refusal: a relation with no service
#       declaration to restate is accepted.
#
# Seeded negatives the SMS requires:
#   SN1  Restating the target service's traffic class yields the duplicate-writer
#        rejection rather than being accepted as independent source truth.
#   SN2  The rejection survives more than one simultaneous offender.
#   SN3  A traffic class with no declared service value to restate is not refused,
#        so absence of a determining fact is not silently treated as a duplicate.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL permission-shape-restatement: $*" >&2; exit 1; }

reg_expr() {
  nix eval --no-write-lock-file --impure --json --expr '
    let
      f = builtins.getFlake "'"path:${repo_root}"'";
      pkgs = import f.inputs.nixpkgs { };
      reg = import "'"${repo_root}"'/lib/derivation-registry/default.nix" { lib = pkgs.lib; };
    in
      '"$1"''
}

# P4 (registry binding): the rule that owns this derivation is registered as
# producing a derivable fact. Without this the refusal below would be raising a
# fault on a rule the registry does not claim.
out="$(reg_expr 'reg.classify { field = "permissionShape"; }')" || {
  fail "P4 the registry could not classify permissionShape
${out}"; }
grep -q '"derivable"' <<<"${out}" || fail "P4 permissionShape is not classified derivable by the registry
${out}"

# P3: a relation targeting an external scope has no service declaration to
# restate, so the rule does not apply and the relation is accepted.
out="$(reg_expr 'reg.ensurePermissionShapeNotRestated {
  site = "site-a";
  serviceTrafficType = { "clients-dns" = "dns"; };
  relations = [
    {
      id = "allow-clients-to-wan";
      from = { kind = "tenant"; name = "cobalt-clients"; };
      to = { kind = "external"; };
      action = "allow";
    }
  ];
}' 2>&1)" || fail "P3 a relation with no service declaration was refused
${out}"

# P3: omitting the traffic class entirely is the intended form, because the rule
# derives it. Accepting it proves the guard is not simply demanding the field.
out="$(reg_expr 'reg.ensurePermissionShapeNotRestated {
  site = "site-a";
  serviceTrafficType = { "clients-dns" = "dns"; };
  relations = [
    {
      id = "allow-clients-to-clients-dns";
      from = { kind = "tenant"; name = "cobalt-clients"; };
      to = { kind = "service"; name = "clients-dns"; };
      action = "allow";
    }
  ];
}' 2>&1)" || fail "P3 a relation that omits the derivable traffic class was refused
${out}"

# SN1: restating the target service's declared traffic class is refused.
set +e
out="$(reg_expr 'reg.ensurePermissionShapeNotRestated {
  site = "site-a";
  serviceTrafficType = { "clients-dns" = "dns"; };
  relations = [
    {
      id = "allow-clients-to-clients-dns";
      from = { kind = "tenant"; name = "cobalt-clients"; };
      to = { kind = "service"; name = "clients-dns"; };
      trafficType = "dns";
      action = "allow";
    }
  ];
}' 2>&1)"
rc=$?
set -e
((rc != 0)) || fail "SN1 restating the target service's traffic class succeeded instead of failing closed"
grep -q 'E_DUPLICATE_WRITER' <<<"${out}" || fail "SN1 the refusal did not carry E_DUPLICATE_WRITER
${out}"

# P2: all five elements the SMS requires are present in the diagnostic.
grep -q 'trafficType' <<<"${out}" || fail "P2 the diagnostic did not name the field
${out}"
grep -q 'allow-clients-to-clients-dns' <<<"${out}" || fail "P2 the diagnostic did not name the declaring scope
${out}"
grep -q 'site-a' <<<"${out}" || fail "P2 the diagnostic did not name the site
${out}"
grep -q 'serviceDeclaration.trafficType' <<<"${out}" || fail "P2 the diagnostic did not name the determining declared fact
${out}"
grep -q 'DRV-SERVICE-PERMISSION-SHAPE' <<<"${out}" || fail "P2 the diagnostic did not name the rule identity
${out}"
grep -qF 'trafficType \"dns\"' <<<"${out}" || fail "P2 the diagnostic did not name the derived value
${out}"
grep -q 'clients-dns' <<<"${out}" || fail "P2 the diagnostic did not name the service that determines the value
${out}"

# P2: the hint tells the reader how to correct it, so the fault is usable without
# guessing which side is wrong.
grep -q 'Drop trafficType from the relation' <<<"${out}" || fail "P2 the diagnostic did not name the correction
${out}"

# SN2: the refusal survives more than one offender in the same model.
set +e
out="$(reg_expr 'reg.ensurePermissionShapeNotRestated {
  site = "site-a";
  serviceTrafficType = { "clients-dns" = "dns"; "dmz-dns" = "dns"; };
  relations = [
    {
      id = "allow-clients-to-clients-dns";
      to = { kind = "service"; name = "clients-dns"; };
      trafficType = "dns";
    }
    {
      id = "allow-dmz-to-dmz-dns";
      to = { kind = "service"; name = "dmz-dns"; };
      trafficType = "dns";
    }
  ];
}' 2>&1)"
rc=$?
set -e
((rc != 0)) || fail "SN2 two simultaneous restatements were accepted instead of failing closed"
grep -q 'E_DUPLICATE_WRITER' <<<"${out}" || fail "SN2 the multi-offender refusal did not carry E_DUPLICATE_WRITER
${out}"

# SN3: a supplied class with no declared service value to restate is not a
# duplicate writer. The determining fact is absent, so nothing is derived and
# nothing can be restated.
out="$(reg_expr 'reg.ensurePermissionShapeNotRestated {
  site = "site-a";
  serviceTrafficType = { "clients-dns" = "dns"; };
  relations = [
    {
      id = "allow-clients-to-unmodelled-dns";
      to = { kind = "service"; name = "unmodelled-dns"; };
      trafficType = "dns";
    }
  ];
}' 2>&1)" || fail "SN3 a traffic class with no declared service value was refused as a duplicate
${out}"

echo "PASS permission-shape-restatement"
