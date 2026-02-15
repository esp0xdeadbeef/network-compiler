{
  cfg,
}:

let
  common = import ./common.nix { inherit cfg; };
  inherit (common) lib cfg;

  topoRaw = import ./10-topology-raw.nix { inherit cfg; };

  topoWithLinks = topoRaw // {
    defaultRouteMode = cfg.defaultRouteMode or "default";
    coreRoutingNodeName = cfg.coreRoutingNodeName or null;

    links = (topoRaw.links or { }) // (cfg.links or { });
  };

  resolved = import ../../lib/topology-resolve.nix {
    inherit lib;
    inherit (cfg) ulaPrefix tenantV4Base;
  } topoWithLinks;

in
import ../../lib/compile/routing-gen.nix {
  inherit lib;
  inherit (cfg)
    ulaPrefix
    tenantV4Base
    policyNodeName
    coreNodeName
    ;
  coreRoutingNodeName = cfg.coreRoutingNodeName or null;
} resolved
