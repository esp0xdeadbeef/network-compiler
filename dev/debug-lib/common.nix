{
  sopsData ? { },
}:
let
  flake = builtins.getFlake (toString ../../.);
  lib = flake.lib;
  cfg = import ./inputs.nix { inherit sopsData; };
in
{
  inherit flake lib cfg;
}
