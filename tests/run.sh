# ./tests/run.sh
#!/usr/bin/env bash

# Unified test runner
#
# 1) Runs NEGATIVE validation tests (must FAIL)
# 2) Evaluates debug pipeline artifacts in ./dev/debug-lib (must SUCCEED)
# 3) Performs “manual sanity checks” on the debug model:
#    - WAN injects internet routes to core (when expected)
#    - policy-core propagates internet routes to policy
#    - policy-access propagates internet routes to access
#    - core has tenant routes back via policy-core
#
# Usage:
#   ./tests/run.sh

set -euo pipefail
shopt -s inherit_errexit

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.."; pwd)"

die() {
  echo >&2 "test case failed: $*"
  exit 1
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
work="$tmp/work"
mkdir -p "$work"
cd "$work"

###############################################################################
# Helpers
###############################################################################

# Evaluate an expression to JSON (strict) and print to stdout
eval_json() {
  local expr="$1"
  nix-instantiate --eval --strict --json --show-trace --expr "$expr"
}

# Evaluate an expression to a raw (non-JSON) nix value string (strict)
eval_raw() {
  local expr="$1"
  nix-instantiate --eval --strict --show-trace --expr "$expr"
}

# Run an expression expecting it to fail
expect_failure_expr() {
  local name="$1"
  local expr="$2"
  if nix-instantiate --eval --strict --json --show-trace --expr "$expr" >"$work/out" 2>"$work/stderr"; then
    die "$name evaluated successfully to $(cat "$work/out"), but it was expected to fail"
  fi
}

# Run an expression expecting it to succeed (JSON-able)
expect_success_expr_json() {
  local name="$1"
  local expr="$2"
  if ! nix-instantiate --eval --strict --json --show-trace --expr "$expr" >"$work/out" 2>"$work/stderr"; then
    cat >&2 "$work/stderr"
    die "$name failed to evaluate"
  fi
}

# Assert a boolean expression is true
assert_true() {
  local name="$1"
  local expr="$2"
  local out
  out="$(eval_raw "$expr" 2>"$work/stderr" || true)"
  if [[ "$out" != "true" ]]; then
    [[ -s "$work/stderr" ]] && cat >&2 "$work/stderr"
    die "$name (expected true, got: $out)"
  fi
}

###############################################################################
# SECTION 1 — NEGATIVE VALIDATION TESTS (MUST FAIL)
###############################################################################

# Important: routing-validation-tests.nix already uses ../lib/eval.nix which
# returns a sanitized attrset (JSON-able), so we can evaluate each test directly
# and require failure.
NEG_LIST_EXPR="
  let
    flake = builtins.getFlake (toString $ROOT);
    lib = flake.lib;
    tests = import $ROOT/tests/routing-validation-tests.nix { inherit lib; };
  in lib.attrNames tests
"

# Get list of negative tests (as bash lines)
mapfile -t NEG_TESTS < <(eval_json "$NEG_LIST_EXPR" | tr -d '[]"' | tr ',' '\n' | sed '/^[[:space:]]*$/d')

for t in "${NEG_TESTS[@]}"; do
  echo "Negative test: $t"
  expect_failure_expr "$t" "
    let
      flake = builtins.getFlake (toString $ROOT);
      lib = flake.lib;
      tests = import $ROOT/tests/routing-validation-tests.nix { inherit lib; };
    in tests.\"$t\"
  "
done

###############################################################################
# SECTION 2 — DEBUG PIPELINE (MUST SUCCEED)
###############################################################################
#
# Your debug files are functions ({ sopsData ? {} }: ...), so we must APPLY them.
# Also: “cannot convert a function to JSON” happens if we evaluate the function
# itself instead of calling it.

echo "Debug: 10-topology-raw"
expect_success_expr_json "debug/10-topology-raw" "import $ROOT/dev/debug-lib/10-topology-raw.nix { }"

echo "Debug: 20-topology-resolved"
expect_success_expr_json "debug/20-topology-resolved" "import $ROOT/dev/debug-lib/20-topology-resolved.nix { }"

echo "Debug: 30-routing"
expect_success_expr_json "debug/30-routing" "import $ROOT/dev/debug-lib/30-routing.nix { }"

echo "Debug: 40-node"
expect_success_expr_json "debug/40-node" "import $ROOT/dev/debug-lib/40-node.nix { }"

echo "Debug: 50-wan"
expect_success_expr_json "debug/50-wan" "import $ROOT/dev/debug-lib/50-wan.nix { }"

echo "Debug: 60-multi-wan"
expect_success_expr_json "debug/60-multi-wan" "import $ROOT/dev/debug-lib/60-multi-wan.nix { }"

echo "Debug: 70-render-networkd"
expect_success_expr_json "debug/70-render-networkd" "import $ROOT/dev/debug-lib/70-render-networkd.nix { }"

echo "Debug: 90-all"
expect_success_expr_json "debug/90-all" "import $ROOT/dev/debug-lib/90-all.nix { }"

echo "Debug: 95-routing-table"
expect_success_expr_json "debug/95-routing-table" "import $ROOT/dev/debug-lib/95-routing-table.nix { }"

###############################################################################
# SECTION 3 — “MANUAL CHECKS” ON DEBUG OUTPUT (BEST PRACTICES)
###############################################################################
#
# This is the stuff you’re eyeballing:
#  - “I added WAN, do we actually get internet routes?”
#  - “Does policy route to access?”
#  - “Does access get routes to internet via policy?”
#  - “Does core know tenant routes via policy?”
#
# We validate those *semantically* from compiled routed.links endpoints.

ROUTED_EXPR="import $ROOT/dev/debug-lib/30-routing.nix { }"

# Extract mode from debug inputs (so the checks adapt)
MODE_EXPR="
  let cfg = import $ROOT/dev/debug-lib/inputs.nix { sopsData = { }; };
  in cfg.defaultRouteMode
"

# True if ANY wan endpoint advertises default v4 or v6
HAS_WAN_DEFAULTS_EXPR="
  let
    flake = builtins.getFlake (toString $ROOT);
    lib = flake.lib;
    routed = $ROUTED_EXPR;
    wans = lib.filter (l: (l.kind or null) == \"wan\") (lib.attrValues (routed.links or { }));
    epHasDefault = ep:
      (lib.any (r: (r.dst or null) == \"0.0.0.0/0\") (ep.routes4 or []))
      || (lib.any (r: (r.dst or null) == \"::/0\") (ep.routes6 or []));
  in
    lib.any (l: lib.any epHasDefault (lib.attrValues (l.endpoints or { }))) wans
"

# policy-core link must exist and both endpoints must have the expected directionality:
# - policy endpoint routes default/computed via core (unless blackhole)
# - core endpoint routes tenants via policy
POLICY_CORE_EXISTS_EXPR="
  let
    routed = $ROUTED_EXPR;
  in
    (routed.links or { }) ? \"policy-core\"
"

CORE_HAS_TENANT_ROUTES_VIA_POLICY_EXPR="
  let
    flake = builtins.getFlake (toString $ROOT);
    lib = flake.lib;
    routed = $ROUTED_EXPR;
    l = (routed.links.\"policy-core\" or (throw \"missing policy-core\"));
    ep = (l.endpoints.\"s-router-core-wan\" or {});
    r4 = ep.routes4 or [];
    r6 = ep.routes6 or [];
    # tenant routes should include at least one 10.10.<vid>.0/24 and one fd42:dead:beef:<vid>::/64
    hasTenant4 = lib.any (r: lib.hasPrefix \"10.10.\" (r.dst or \"\") && lib.hasSuffix \"/24\" (r.dst or \"\")) r4;
    hasTenant6 = lib.any (r: lib.hasPrefix \"fd42:dead:beef:\" (r.dst or \"\") && lib.hasSuffix \"/64\" (r.dst or \"\")) r6;
  in
    hasTenant4 && hasTenant6
"

POLICY_HAS_UPSTREAM_INTERNET_EXPR="
  let
    flake = builtins.getFlake (toString $ROOT);
    lib = flake.lib;
    mode = $MODE_EXPR;
    routed = $ROUTED_EXPR;
    l = (routed.links.\"policy-core\" or (throw \"missing policy-core\"));
    ep = (l.endpoints.\"s-router-policy-only\" or {});
    r4 = ep.routes4 or [];
    r6 = ep.routes6 or [];
    hasAny4 = r4 != [];
    hasAny6 = r6 != [];
    hasDefault4 = lib.any (r: (r.dst or \"\") == \"0.0.0.0/0\") r4;
    hasDefault6 = lib.any (r: (r.dst or \"\") == \"::/0\") r6;
  in
    if mode == \"blackhole\" then
      (!hasDefault4) && (!hasDefault6) && (!hasAny4) && (!hasAny6)
    else if mode == \"computed\" then
      hasAny4 && hasAny6
    else
      hasDefault4 && hasDefault6
"

ACCESS_HAS_INTERNET_VIA_POLICY_EXPR="
  let
    flake = builtins.getFlake (toString $ROOT);
    lib = flake.lib;
    mode = $MODE_EXPR;
    routed = $ROUTED_EXPR;
    l = (routed.links.\"policy-access-10\" or (throw \"missing policy-access-10\"));
    ep = (l.endpoints.\"s-router-access-10\" or {});
    r4 = ep.routes4 or [];
    r6 = ep.routes6 or [];

    hasAny4 = r4 != [];
    hasAny6 = r6 != [];

    hasDefault4 = lib.any (r: (r.dst or \"\") == \"0.0.0.0/0\") r4;
    hasDefault6 = lib.any (r: (r.dst or \"\") == \"::/0\") r6;

    # always expect ULA aggregate route on access (policy-access adds ula48)
    hasUla48 = lib.any (r: (r.dst or \"\") == \"fd42:dead:beef::/48\") r6;
  in
    if mode == \"blackhole\" then
      (r4 == []) && (!hasDefault6) && hasUla48
    else if mode == \"computed\" then
      hasAny4 && hasAny6 && hasUla48
    else
      hasDefault4 && hasDefault6 && hasUla48
"

# WAN defaults are expected only if mode == default (your assertions enforce this)
# BUT: your debug inputs.nix currently injects defaults into links only when mode == default.
WAN_DEFAULTS_EXPECTED_EXPR="
  let mode = $MODE_EXPR; in mode == \"default\"
"

echo "Checks: debug routing sanity"

assert_true "policy-core link exists" "$POLICY_CORE_EXISTS_EXPR"
assert_true "core has tenant routes via policy-core" "$CORE_HAS_TENANT_ROUTES_VIA_POLICY_EXPR"
assert_true "policy has upstream internet routes (mode-aware)" "$POLICY_HAS_UPSTREAM_INTERNET_EXPR"
assert_true "access has internet routes via policy-access (mode-aware)" "$ACCESS_HAS_INTERNET_VIA_POLICY_EXPR"

# WAN default checks only when expected by mode
if [[ "$(eval_raw "$WAN_DEFAULTS_EXPECTED_EXPR")" == "true" ]]; then
  assert_true "WAN advertises at least one default route (mode=default)" "$HAS_WAN_DEFAULTS_EXPR"
else
  echo "Checks: skipping WAN-default assertion (mode != default)"
fi

###############################################################################
# DONE
###############################################################################
echo >&2 "ALL TESTS OK"

