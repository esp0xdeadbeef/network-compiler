# ./dev/debug-lib/30-routing.nix
# FILE: ./dev/debug-lib/30-routing.nix
{
  sopsData ? { },
}:
let
  pkgs = null;
  flake = builtins.getFlake (toString ../../.);
  lib = flake.lib;
  cfg = import ./inputs.nix { inherit sopsData; };

  # Build raw topology, then merge debug links/WAN links BEFORE resolving,
  # so topology-resolve can materialize endpoint-declared context nodes
  # like "${coreNodeName}-isp-2".
  topoRaw = import ./10-topology-raw.nix { inherit sopsData; };

  # coreNodeName is FABRIC HOST
  coreNodeName = cfg.coreNodeName or "s-router-core";

  haveWan = builtins.isAttrs sopsData && (sopsData ? wan) && builtins.isAttrs sopsData.wan;

  mkWanLink =
    ctx: wan:
    let
      coreCtx = "${coreNodeName}-${ctx}";
    in
    {
      kind = "wan";
      carrier = "wan";
      vlanId = wan.vlanId or 6;
      name = "wan-${ctx}";
      members = [ coreNodeName ];
      endpoints = {
        "${coreCtx}" =
          {
            routes4 = lib.optional (wan ? ip4) { dst = "0.0.0.0/0"; };
            routes6 = lib.optional (wan ? ip6) { dst = "::/0"; };
          }
          // lib.optionalAttrs (wan ? ip4) { addr4 = wan.ip4; }
          // lib.optionalAttrs (wan ? ip6) { addr6 = wan.ip6; }
          // lib.optionalAttrs (wan ? acceptRA) { acceptRA = wan.acceptRA; }
          // lib.optionalAttrs (wan ? dhcp) { dhcp = wan.dhcp; };
      };
    };

  wanLinks = if haveWan then lib.mapAttrs (ctx: wan: mkWanLink ctx wan) sopsData.wan else { };

  topoWithLinks = topoRaw // {
    defaultRouteMode = cfg.defaultRouteMode or "default";
    coreRoutingNodeName = cfg.coreRoutingNodeName or null;

    # Ensure resolver sees these extra links (cfg.links + WAN links).
    links = (topoRaw.links or { }) // (cfg.links or { }) // wanLinks;
  };

  resolved = import ../../lib/topology-resolve.nix {
    inherit lib;
    inherit (cfg) ulaPrefix tenantV4Base;
  } topoWithLinks;

in
import ../../lib/compile/routing-gen.nix {
  inherit lib;
  inherit (cfg) ulaPrefix tenantV4Base;

  # fabric host
  inherit coreNodeName;

  # optional: explicit routing context for policy-core
  coreRoutingNodeName = cfg.coreRoutingNodeName or null;

  policyNodeName = cfg.policyNodeName or "s-router-policy-only";
} resolved

