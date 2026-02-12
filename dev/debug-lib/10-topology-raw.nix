{ sopsData ? {} }:
let
  pkgs = null;
  lib = import <nixpkgs/lib>;
  cfg = import ./inputs.nix { inherit sopsData; };
in
import ../../lib/topology-gen.nix { inherit lib; } {
  inherit (cfg)
    tenantVlans
    policyAccessTransitBase
    corePolicyTransitVlan
    ulaPrefix
    tenantV4Base
    ;
}

