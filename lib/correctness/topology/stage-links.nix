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

  tenantAttachmentNames = node:
    lib.filter (t: t != null) (
      map (attachment:
        if (attachment.kind or null) == "tenant" then attachment.name or null else null
      ) (node.attachments or [ ])
    );

  validateCanonicalStageLink =
    siteKey: nodes: overlays: pair:
    let
      a = builtins.elemAt pair 0;
      b = builtins.elemAt pair 1;
      roleA = nodes.${a}.role or null;
      roleB = nodes.${b}.role or null;
      idxA = stageIndex.${roleA} or null;
      idxB = stageIndex.${roleB} or null;
      distance = if idxA == null || idxB == null then null else idxA - idxB;
      adjacent = distance == 1 || distance == (-1);
      # Provider handoff / virtual adapter: access<->core with shared tenant attachment
      sharedTenants = lib.intersectLists (tenantAttachmentNames nodes.${a}) (tenantAttachmentNames nodes.${b});
      isProviderHandoff =
        (roleA == "access" && roleB == "core" || roleA == "core" && roleB == "access")
        && builtins.length sharedTenants > 0;
    in
    ensure (idxA != null && idxB != null && (adjacent || isProviderHandoff)) {
      code = "E_TOPO_NON_CANONICAL_STAGE_LINK";
      site = siteKey;
      path = [
        "topology"
        "links"
      ];
      message = "topology link '${a}' (${toString roleA}) <-> '${b}' (${toString roleB}) bypasses the canonical staged fabric";
      hints = [
        "Allowed adjacencies are access <-> downstream-selector <-> policy <-> upstream-selector <-> core."
        "Do not model direct core-to-access, core-to-core, core-to-policy, access-to-policy, or selector-bypassing links."
        "Direct access-to-core links are allowed only when both nodes share a tenant attachment (provider handoff / virtual adapter such as PPPoE, WireGuard, Nebula)."
        "If traffic needs to cross core functions, express it as policy-controlled traversal through the canonical stages."
      ];
    };

  validateCanonicalStageLinks =
    siteKey: nodes: overlays: links:
    let
      _links = builtins.foldl'
        (
          acc: pair: acc && validateCanonicalStageLink siteKey nodes overlays pair
        )
        true
        links;
      _policyTraversal = (import ./policy-traversal.nix { inherit lib; }).validatePolicyTraversal siteKey nodes links;
    in
    _links && _policyTraversal;

in
{
  inherit validateCanonicalStageLinks;
}
