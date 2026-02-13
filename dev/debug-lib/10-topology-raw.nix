{
  sopsData ? { },
}:
let
  pkgs = null;
  flake = builtins.getFlake (toString ../../.);
  lib = flake.lib;
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

  forbiddenVlanRanges = cfg.forbiddenVlanRanges or [ ];
}
