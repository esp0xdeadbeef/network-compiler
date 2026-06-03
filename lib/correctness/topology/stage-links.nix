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

  tenantAttachments =
    node:
    lib.filter (tenant: tenant != null) (
      map
        (attachment:
          if (attachment.kind or null) == "tenant" then attachment.name or null else null
        )
        (node.attachments or [ ])
    );

  isSharedAttachmentCoreAccess =
    nodes: a: b:
    let
      roleA = nodes.${a}.role or null;
      roleB = nodes.${b}.role or null;
      core = if roleA == "core" && roleB == "access" then a else if roleB == "core" && roleA == "access" then b else null;
      access = if roleA == "access" && roleB == "core" then a else if roleB == "access" && roleA == "core" then b else null;
      coreTenants = if core == null then [ ] else tenantAttachments nodes.${core};
      accessTenants = if access == null then [ ] else tenantAttachments nodes.${access};
    in
    core != null
    && access != null
    && builtins.any (tenant: builtins.elem tenant accessTenants) coreTenants;

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
      sharedAttachmentCoreAccess = isSharedAttachmentCoreAccess nodes a b;
    in
    ensure (idxA != null && idxB != null && (adjacent || sharedAttachmentCoreAccess)) {
      code = "E_TOPO_NON_CANONICAL_STAGE_LINK";
      site = siteKey;
      path = [
        "topology"
        "links"
      ];
      message = "topology link '${a}' (${toString roleA}) <-> '${b}' (${toString roleB}) bypasses the canonical staged fabric";
      hints = [
        "Allowed adjacencies are access <-> downstream-selector <-> policy <-> upstream-selector <-> core."
        "A core <-> access link is only valid when the core and access node share an explicit attachment scope."
        "Do not model direct core-to-core, core-to-policy, access-to-policy, or selector-bypassing links."
        "If traffic needs to cross core functions, express it as policy-controlled traversal through the canonical stages."
      ];
    };

  validateCanonicalStageLinks =
    siteKey: nodes: overlays: links:
    builtins.foldl'
      (
        acc: pair: acc && validateCanonicalStageLink siteKey nodes overlays pair
      )
      true
      links;

in
{
  inherit validateCanonicalStageLinks;
}
