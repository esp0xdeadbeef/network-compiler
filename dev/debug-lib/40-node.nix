{ sopsData ? {} }:
let
  pkgs = null;
  lib = import <nixpkgs/lib>;
  cfg = import ./inputs.nix { inherit sopsData; };

  node = "s-router-access-10";

  routed = import ./30-routing.nix { inherit sopsData; };
in
import ./view-node.nix {
  inherit lib pkgs;
  inherit (cfg) ulaPrefix tenantV4Base;
} node routed

