# ./tests/run.sh
#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

fail() {
  echo
  echo "============================================================"
  echo "FAILED: $1"
  echo "============================================================"
  exit 1
}

section() {
  echo
  echo "============================================================"
  echo "$1"
  echo "============================================================"
}

run_negative_tests() {
  section "Running negative routing validation tests (flake)"

  nix flake check \
    --no-build \
    --print-build-logs \
    --show-trace \
    --all-systems \
    || fail "flake checks failed"

  echo "FLAKE CHECKS OK"
}

run_eval_negative() {
  section "Running negative eval tests"

  nix eval --show-trace --impure --raw --expr '
    let
      flake = builtins.getFlake (toString ./.);
      lib = flake.lib;
    in
      import ./tests/evaluate-negative.nix { inherit lib; }
  ' || fail "evaluate-negative.nix failed"

  echo
  echo "NEGATIVE TESTS OK"
}

run_eval_positive() {
  section "Running positive eval tests"

  nix eval --show-trace --impure --raw --expr '
    let
      flake = builtins.getFlake (toString ./.);
      lib = flake.lib;
    in
      import ./tests/evaluate-positive.nix { inherit lib; }
  ' || fail "evaluate-positive.nix failed"

  echo
  echo "POSITIVE TESTS OK"
}

run_routing_validation_suite() {
  section "Running routing validation suite"

  nix eval --show-trace --impure --raw --expr '
    let
      flake = builtins.getFlake (toString ./.);
      lib = flake.lib;
    in
      import ./tests/routing-validation-test.nix { inherit lib; }
  ' || fail "routing-validation-test.nix failed"

  echo
  echo "ROUTING VALIDATION TESTS OK"
}

run_routing_semantics_suite() {
  section "Running routing semantics (convergence invariants) suite"

  nix eval --show-trace --impure --raw --expr '
    let
      flake = builtins.getFlake (toString ./.);
      lib = flake.lib;
    in
      import ./tests/routing-semantics-positive.nix { inherit lib; }
  ' || fail "routing-semantics-positive.nix failed"

  echo
  echo "ROUTING SEMANTICS TESTS OK"
}

run_debug_targets() {
  section "Running debug targets"

  nix eval --show-trace --impure --expr 'import ./dev/debug-lib/10-topology-raw.nix { }' >/dev/null \
    || fail "10-topology-raw failed"

  nix eval --show-trace --impure --expr 'import ./dev/debug-lib/20-topology-resolved.nix { }' >/dev/null \
    || fail "20-topology-resolved failed"

  nix eval --show-trace --impure --expr 'import ./dev/debug-lib/30-routing.nix { }' >/dev/null \
    || fail "30-routing failed"

  nix eval --show-trace --impure --expr 'import ./dev/debug-lib/40-node.nix { }' >/dev/null \
    || fail "40-node failed"

  nix eval --show-trace --impure --expr 'import ./dev/debug-lib/50-wan.nix { }' >/dev/null \
    || fail "50-wan failed"

  nix eval --show-trace --impure --expr 'import ./dev/debug-lib/60-multi-wan.nix { }' >/dev/null \
    || fail "60-multi-wan failed"

  nix eval --show-trace --impure --expr 'import ./dev/debug-lib/70-render-networkd.nix { }' >/dev/null \
    || fail "70-render-networkd failed"

  nix eval --show-trace --impure --expr 'import ./dev/debug-lib/90-all.nix { }' >/dev/null \
    || fail "90-all failed"

  nix eval --show-trace --impure --expr 'import ./dev/debug-lib/95-routing-table.nix { }' >/dev/null \
    || fail "95-routing-table failed"

  echo "DEBUG TARGETS OK"
}

echo "=== nixos-network-compiler test runner ==="

run_negative_tests
run_eval_negative
run_eval_positive
run_routing_validation_suite
run_routing_semantics_suite
run_debug_targets

echo
echo "============================================================"
echo "ALL TESTS OK"
echo "============================================================"

