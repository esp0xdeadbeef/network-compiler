{
  sopsData ? { },
}:
let
  common = import ./common.nix { inherit sopsData; };
  inherit (common) lib cfg;

  raw = import ./10-topology-raw.nix { inherit sopsData; };
in
import ../../lib/topology-resolve.nix {
  inherit lib;
  inherit (cfg) ulaPrefix tenantV4Base;
} raw
