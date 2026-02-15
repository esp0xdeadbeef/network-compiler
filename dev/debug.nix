{ lib }:

path:

let
  fabric = import ../lib/main.nix { nix.lib = lib; };
  result = fabric.fromFile path;
in
result
