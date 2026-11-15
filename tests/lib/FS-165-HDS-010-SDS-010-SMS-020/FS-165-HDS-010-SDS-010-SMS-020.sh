#!/usr/bin/env bash
# GAMP-ID: FS-165-HDS-010-SDS-010-SMS-020
# GAMP-SCOPE: software-module-test
#
# SPEC:   GAMP/SMS/FS-165-HDS-010-SDS-010-SMS-020.md
# OWNER:  network-compiler
# MODULE: Repetitive Source-Form Refusal  (lib/source-form/minimality.nix)
#
# Behavioural case against the real module. The qualifier suffix keeps this case
# distinct from the network-codex-agent case that holds the manifest-side contract
# for the same row: this case owns the intent-source consequence, where the
# compiler refuses a source that grows by rewriting one record per scope.
#
# Predicates from SMS-020 module responsibilities:
#   P1  Duplicated classification is detected: the same record rewritten per
#       scope is refused rather than accepted as N independent declarations.
#   P2  A field a downstream layer can derive is not source truth. A source that
#       declares each fact once is accepted however long it is, so the check
#       refuses padding and not size. A table row repeated per fact is dry, not
#       padded, and must be accepted.
#   P3  The normalized review record carries what a reviewer needs: line count,
#       distinct-shape count, ratio, budget, and the worst repeated shape.
#   P4  The diagnostic keeps the boundary visible: it states that size is not the
#       defect, so a reader does not respond by deleting declarations.
#
# Seeded negatives:
#   SN1  A record rewritten per scope is REFUSED with E_SOURCE_FORM_REPETITION.
#   SN2  Renaming the identifiers in the repeated record does not hide it.
#   SN3  A single clean record is ACCEPTED, so the refusal is not a blanket one.
#   SN4  The refusal is reachable through the compiler path entrypoint and runs
#        before evaluation, so a recursive source cannot reach the model.
set -euo pipefail

repo_root="${SMS_TEST_REPO_ROOT:-$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel)}"
source "${repo_root}/tests/lib/direct-test-guard.sh"

fail() { echo "FAIL source-form-repetition: $*" >&2; exit 1; }

sf_expr() {
  nix eval --no-write-lock-file --impure --json --expr '
    let
      f = builtins.getFlake "'"path:${repo_root}"'";
      pkgs = import f.inputs.nixpkgs { };
      sf = import "'"${repo_root}"'/lib/source-form/minimality.nix" { lib = pkgs.lib; };
    in
      '"$1"''
}

# A data table: one row per tenant, no brace in any row. This is the dry form the
# check must reward, so it is built once and reused.
table_text='builtins.concatStringsSep "\n" (builtins.genList (i: "  tenant${toString i} = \"10.${toString i}.0.0/24\";") 300)'

# The bible form: one record rewritten per scope, every record brace-bearing.
bible_text='builtins.concatStringsSep "\n" (builtins.concatLists (builtins.genList (i: [
  "    { id = \"allow-tenant${toString i}-to-wan\"; priority = ${toString i}; }"
  "    { to = \"external\"; action = \"allow\"; returnBehavior = \"symmetric\"; }"
]) 200))'

# SN3: a single clean record is accepted. Without this the seeded negatives below
# would be satisfied by a module that refuses everything.
out="$(sf_expr "sf.assertMinimal { text = builtins.concatStringsSep \"\\n\" [
  \"{\"
  \"  relations = [\"
  \"    { id = \\\"allow-clients-to-wan\\\"; to = \\\"external\\\"; }\"
  \"  ];\"
  \"}\"
]; }")" || fail "SN3 a single clean record was refused, so the check is a blanket refusal
${out}"

# P2: a 300-row data table declares each fact once and must be accepted. This is
# the predicate that stops the check from punishing the dry form it exists for.
out="$(sf_expr "let r = sf.analyze { text = ${table_text}; }; in { ok = r.ok; structural = r.lineTotal; }")" || fail "P2 the data table could not be analysed
${out}"
grep -q '"ok":true' <<<"${out}" || fail "P2 a 300-row data table was refused, so the check punishes a dry table
${out}"
grep -q '"structural":0' <<<"${out}" || fail "P2 the table contributed structural lines, so data rows are being counted as records
${out}"

# SN1: the same record rewritten per scope is refused.
set +e
out="$(sf_expr "sf.assertMinimal { text = ${bible_text}; }" 2>&1)"
rc=$?
set -e
((rc != 0)) || fail "SN1 a record rewritten per scope was accepted instead of refused"
grep -q 'E_SOURCE_FORM_REPETITION' <<<"${out}" || fail "SN1 the refusal did not carry E_SOURCE_FORM_REPETITION
${out}"

# P3: the refusal carries the review record a reviewer needs.
grep -q 'distinct shapes' <<<"${out}" || fail "P3 the diagnostic did not name the distinct-shape count
${out}"
grep -q 'budget' <<<"${out}" || fail "P3 the diagnostic did not name the budget
${out}"
grep -q 'recurs' <<<"${out}" || fail "P3 the diagnostic did not name the worst repeated shape
${out}"
grep -q 'Write the repeated shape once' <<<"${out}" || fail "P3 the diagnostic did not name the correction
${out}"

# P4: the boundary stays visible, so a reader does not delete declarations to
# satisfy the budget.
grep -q 'Size is not the defect' <<<"${out}" || fail "P4 the diagnostic did not disclaim size as the defect
${out}"

# SN2: masking makes renaming irrelevant. Two sources differing only in identifier
# choice must reach the same verdict, so repetition cannot be hidden by renaming.
for prefix in "clients-" "iot-srv-"; do
  out="$(sf_expr "let r = sf.analyze { text = builtins.concatStringsSep \"\\n\" (builtins.concatLists (builtins.genList (i: [
    \"    { id = \\\"allow-${prefix}\${toString i}-to-wan\\\"; priority = \${toString i}; }\"
    \"    { to = \\\"external\\\"; action = \\\"allow\\\"; returnBehavior = \\\"symmetric\\\"; }\"
  ]) 200)); }; in { ok = r.ok; distinct = r.distinctLines; }")" || fail "SN2 could not analyse the '${prefix}' renaming
${out}"
  grep -q '"ok":false' <<<"${out}" || fail "SN2 the '${prefix}' renaming escaped the repetition check
${out}"
done

# SN4: the refusal is on the compiler path and runs before evaluation. The fixture
# is deliberately not valid Nix: if the gate did not run first, evaluation would
# fail with a parse error instead of the source-form fault.
tmp_dir="$(mktemp -d)"
trap 'rm -rf "${tmp_dir}"' EXIT
bible="${tmp_dir}/intent.nix"
for i in $(seq 1 200); do
  printf '    { id = "allow-tenant%s-to-wan"; priority = %s; }\n' "${i}" "${i}" >>"${bible}"
  printf '    { to = "external"; action = "allow"; returnBehavior = "symmetric"; }\n' >>"${bible}"
done

set +e
out="$(nix eval --no-write-lock-file --impure --expr '
let f = builtins.getFlake "'"path:${repo_root}"'";
in f.lib.compilePath "x86_64-linux" "'"${bible}"'"' 2>&1)"
rc=$?
set -e
((rc != 0)) || fail "SN4 the compiler path entrypoint accepted a repetitive source"
grep -q 'E_SOURCE_FORM_REPETITION' <<<"${out}" || fail "SN4 the entrypoint refusal did not carry E_SOURCE_FORM_REPETITION, so the gate is not on the path
${out}"

echo "PASS source-form-repetition"
