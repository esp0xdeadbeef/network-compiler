{
  sopsData ? { },
}:
let
  pkgs = null;
  flake = builtins.getFlake (toString ../../.);
  lib = flake.lib;

  routed = import ./30-routing.nix { inherit sopsData; };

  q = import ../../lib/query/routing-table.nix { inherit lib; };
in
q routed

