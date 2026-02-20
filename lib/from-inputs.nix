{ lib }:

sites:

let
  compileSite = import ./compile-site.nix { inherit lib; };
  invariants = import ./fabric/invariants { inherit lib; };

  normalize = import ./normalize/from-user-input.nix { inherit lib; };

  _global = builtins.deepSeq (invariants.checkAll { inherit sites; }) true;

  compiled = lib.mapAttrs (
    name: cfg:
    let
      site = normalize cfg;
      result = compileSite site;
    in
    builtins.deepSeq result result
  ) sites;

in
builtins.deepSeq _global compiled
