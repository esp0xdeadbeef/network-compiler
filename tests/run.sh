# ./tests/run.sh
#!/usr/bin/env bash
set -euo pipefail

echo "=== nixos-network-compiler test runner ==="
echo

echo "============================================================"
echo "Running negative routing validation tests (flake)"
echo "============================================================"
nix flake check --no-build
echo "FLAKE CHECKS OK"
echo

echo "============================================================"
echo "Running negative eval tests"
echo "============================================================"
nix eval --raw --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    lib = flake.lib;
  in
    import ./tests/evaluate-negative.nix { inherit lib; }
'
echo "NEGATIVE TESTS OK"
echo

echo "============================================================"
echo "Running positive eval tests"
echo "============================================================"
nix eval --raw --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    lib = flake.lib;
  in
    import ./tests/evaluate-positive.nix { inherit lib; }
'
echo "POSITIVE TESTS OK"
echo

echo

echo "============================================================"
echo "Running routing validation suite"
echo "============================================================"
nix eval --raw --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    lib = flake.lib;
  in
    import ./tests/routing-validation-test.nix { inherit lib; }
'
echo "ROUTING VALIDATION TESTS OK"
echo

echo "============================================================"
echo "Running routing semantics (convergence invariants) suite"
echo "============================================================"
nix eval --raw --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    lib = flake.lib;
  in
    import ./tests/routing-semantics-positive.nix { inherit lib; }
'
echo "ROUTING SEMANTICS OK"
echo

echo "============================================================"
echo "Running multi-site evaluation (all sites)"
echo "============================================================"
nix eval --raw --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    lib = flake.lib;
    multi = import ./examples/multi-site { sopsData = { }; };
    eval = import ./lib/eval.nix { inherit lib; };
    results = lib.mapAttrs (_: v: eval { topology = v; }) multi;
  in
    builtins.deepSeq results "MULTISITE EVAL OK"
'
echo "MULTISITE EVAL OK"
echo

echo "============================================================"
echo "Running overlay (nebula) route verification"
echo "============================================================"
nix eval --raw --impure --expr '
  let
    flake = builtins.getFlake (toString ./.);
    lib = flake.lib;
    multi = import ./examples/multi-site { sopsData = { }; };
    eval = import ./lib/eval.nix { inherit lib; };

    hasNebulaRoute =
      routed:
      let
        links = routed.links or { };
        wanLinks = lib.filterAttrs (_: l: (l.name or "") == "nebula") links;
      in
        wanLinks != { };

    checked =
      lib.mapAttrs (_: v:
        let r = eval { topology = v; };
        in if hasNebulaRoute r then true else throw "Missing nebula link"
      ) multi;
  in
    builtins.deepSeq checked "NEBULA ROUTES OK"
'
echo "NEBULA ROUTES OK"
echo

echo "============================================================"
echo "ALL TESTS OK"
echo "============================================================"

