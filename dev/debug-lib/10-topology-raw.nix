{
  sopsData ? { },
}:
let
  common = import ./common.nix { inherit sopsData; };
  inherit (common) lib cfg;
in
import ../../lib/topology-gen.nix { inherit lib; } {
  inherit (cfg)
    tenantVlans
    policyAccessTransitBase
    corePolicyTransitVlan
    ulaPrefix
    tenantV4Base
    policyNodeName
    coreNodeName
    ;

  forbiddenVlanRanges = cfg.forbiddenVlanRanges or [ ];
}
