{ lib }:

let
  util = import ../util.nix { inherit lib; };
  inherit (util) ensure;

  stageIndex = {
    access = 0;
    downstream-selector = 1;
    policy = 2;
    upstream-selector = 3;
    core = 4;
  };

  validateCanonicalStageLink =
    siteKey: nodes: pair:
    let
      a = builtins.elemAt pair 0;
      b = builtins.elemAt pair 1;
      roleA = nodes.${a}.role or null;
      roleB = nodes.${b}.role or null;
      idxA = stageIndex.${roleA} or null;
      idxB = stageIndex.${roleB} or null;
      distance = if idxA == null || idxB == null then null else idxA - idxB;
      adjacent = distance == 1 || distance == (-1);
    in
    ensure (idxA != null && idxB != null && adjacent) {
      code = "E_TOPO_NON_CANONICAL_STAGE_LINK";
      site = siteKey;
      path = [
        "topology"
        "links"
      ];
      message = "topology link '${a}' (${toString roleA}) <-> '${b}' (${toString roleB}) bypasses the canonical staged fabric";
      hints = [
        "Allowed adjacencies are access <-> downstream-selector <-> policy <-> upstream-selector <-> core."
        "Do not model direct core-to-core, core-to-policy, access-to-policy, or selector-bypassing links."
        "If traffic needs to cross core functions, express it as policy-controlled traversal through the canonical stages."
      ];
    };

  validateCanonicalStageLinks =
    siteKey: nodes: links:
    builtins.foldl'
      (
        acc: pair: acc && validateCanonicalStageLink siteKey nodes pair
      )
      true
      links;

in
{
  inherit validateCanonicalStageLinks;
}
