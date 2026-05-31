{ lib }:

let
  util = import ../util.nix { inherit lib; };
  inherit (util) ensure;

  linkConnects =
    a: b: pair:
    let
      x = builtins.elemAt pair 0;
      y = builtins.elemAt pair 1;
    in
    (x == a && y == b) || (x == b && y == a);
in
{
  validateCoreStageAdjacency =
    siteKey: nodes: normalizedLinks: overlayUnderlayVirtualLinks:
    let
      nodeNames = builtins.attrNames nodes;
      coreNodes = lib.filter (n: (nodes.${n}.role or null) == "core") (
        lib.sort builtins.lessThan nodeNames
      );
      upstreamSelectorNodes = lib.filter (n: (nodes.${n}.role or null) == "upstream-selector") nodeNames;
      coreHasActualUpstreamSelector =
        core:
        builtins.any
          (
            upstream:
            builtins.any (linkConnects core upstream) normalizedLinks
          )
          upstreamSelectorNodes;
      coreHasOverlayUnderlayAccess =
        core:
        builtins.any
          (
            pair:
            let
              a = builtins.elemAt pair 0;
              b = builtins.elemAt pair 1;
              other = if a == core then b else if b == core then a else null;
            in
            other != null && (nodes.${other}.role or null) == "access"
          )
          overlayUnderlayVirtualLinks;
    in
    builtins.foldl'
      (
        acc: core:
        acc
        && ensure (coreHasActualUpstreamSelector core || coreHasOverlayUnderlayAccess core) {
          code = "E_CORE_STAGE_ADJACENCY_REQUIRED";
          site = siteKey;
          path = [
            "topology"
            "links"
          ];
          message = "core node '${core}' must have canonical upstream reachability through an upstream-selector or explicit overlay underlay access";
          hints = [
            "WAN/ISP cores normally use an explicit core <-> upstream-selector topology link."
            "Overlay termination cores may satisfy upstream reachability through transport.overlays[].underlayAccess when they are modeled as client-LAN members."
            "Do not add a renderer/inventory P2P adapter for an overlay core that is intended to be a DHCP/SLAAC client on the selected underlay access tenant."
          ];
        }
      )
      true
      coreNodes;
}
