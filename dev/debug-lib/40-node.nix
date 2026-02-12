# FILE: ./dev/debug-lib/40-node.nix
{
  sopsData ? { },
}:
let
  pkgs = null;
  flake = builtins.getFlake (toString ../../.);
  lib = flake.lib;
  cfg = import ./inputs.nix { inherit sopsData; };

  node = "s-router-access-10";

  routed = import ./30-routing.nix { inherit sopsData; };
in
import ./view-node.nix {
  inherit lib pkgs;
  inherit (cfg) ulaPrefix tenantV4Base;
} node routed
