# ./dev/debug-lib/60-multi-wan.nix
{
  sopsData ? { },
}:
let
  pkgs = null;
  flake = builtins.getFlake (toString ../../.);
  lib = flake.lib;

  routed = import ./30-routing.nix { inherit sopsData; };

  q = import ../../lib/query/multi-wan.nix { inherit lib; };
in
q routed

