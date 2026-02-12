# FILE: ./dev/debug-lib/debug-eval.nix
{
  sopsData ? { },
}:
let
  pkgs = null;
  flake = builtins.getFlake (toString ../../.);
  lib = flake.lib;

  cfg = import ./inputs.nix { inherit sopsData; };

  raw = import ../../lib/topology-gen.nix { inherit lib; } {
    inherit (cfg)
      tenantVlans
      policyAccessTransitBase
      corePolicyTransitVlan
      ulaPrefix
      tenantV4Base
      ;
  };

  resolved = import ../../lib/topology-resolve.nix {
    inherit lib;
    inherit (cfg) ulaPrefix tenantV4Base;
  } raw;

  resolvedWithDebugLinks = resolved // {
    links = (resolved.links or { }) // (cfg.links or { });
  };

  routed = import ../../lib/compile/routing-gen.nix {
    inherit lib;
    inherit (cfg) ulaPrefix tenantV4Base;
  } resolvedWithDebugLinks;

in
{
  topology = {
    domain = routed.domain;
    nodes = lib.attrNames routed.nodes;
    links = lib.attrNames routed.links;
  };

  nodes = lib.mapAttrs (
    n: _:
    import ./view-node.nix {
      inherit lib pkgs;
      inherit (cfg) ulaPrefix tenantV4Base;
    } n routed
  ) routed.nodes;
}
