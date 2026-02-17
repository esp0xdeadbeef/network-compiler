{ lib }:

sites:

let
  compileSite = import ./compile-site.nix { inherit lib; };
in
lib.mapAttrs (_: cfg: compileSite cfg) sites
