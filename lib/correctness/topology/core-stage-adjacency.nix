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
    siteKey: nodes: normalizedLinks:
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
    in
    builtins.foldl'
      (
        acc: core:
        acc
        && ensure (coreHasActualUpstreamSelector core) {
          code = "E_CORE_STAGE_ADJACENCY_REQUIRED";
          site = siteKey;
          path = [
            "topology"
            "links"
          ];
          message = "core node '${core}' must have an explicit topology link to an upstream-selector";
          hints = [
            "Keep every core, including overlay termination cores, attached to the canonical payload fabric with core <-> upstream-selector."
            "Do not let an overlay underlay access attachment or virtual core <-> access edge satisfy payload-fabric connectivity."
            "Model daemon underlay access with transport.overlays[].underlayAccess separately from payload ingress to the overlay core."
          ];
        }
      )
      true
      coreNodes;
}
