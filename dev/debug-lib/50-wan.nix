# ./dev/debug-lib/50-wan.nix
{
  sopsData ? { },
}:
let
  pkgs = null;
  flake = builtins.getFlake (toString ../../.);
  lib = flake.lib;

  routed = import ./30-routing.nix { inherit sopsData; };

  q = import ../../lib/query/wan.nix { inherit lib; };
in
q routed

