{ lib }:

sites:

let
  compileSite = import ./compile-site.nix { inherit lib; };
  invariants = import ./fabric/invariants { inherit lib; };

  _global = builtins.deepSeq (invariants.checkAll { inherit sites; }) true;

  compiled = lib.mapAttrs (
    _: cfg:
    let
      result = compileSite cfg;
    in
    builtins.deepSeq result result
  ) sites;

in
builtins.deepSeq _global compiled
