{
  sopsData ? { },
}:
let
  common = import ./common.nix { inherit sopsData; };
  inherit (common) lib cfg;

  node = "s-router-access-10";
  routed = import ./30-routing.nix { inherit sopsData; };
in
import ./view-node.nix {
  inherit lib;
  inherit (cfg) ulaPrefix tenantV4Base;
} node routed
