{ lib }:

let
  tenantAttachments =
    node:
    lib.filter (tenant: tenant != null) (
      map (attachment: if (attachment.kind or null) == "tenant" then attachment.name or null else null) (
        node.attachments or [ ]
      )
    );
in
{
  overlayUnderlayVirtualLinks =
    nodes: overlays:
    let
      nodeNames = builtins.attrNames nodes;
      accessNodesForTenant =
        tenant:
        lib.filter (
          nodeName:
          (nodes.${nodeName}.role or null) == "access"
          && builtins.elem tenant (tenantAttachments nodes.${nodeName})
        ) nodeNames;
      linkForOverlay =
        overlay:
        let
          cores = overlay.terminateOn or [ ];
          underlayAccess = overlay.underlayAccess or { };
          tenant =
            if builtins.isAttrs underlayAccess && (underlayAccess.kind or null) == "tenant" then
              underlayAccess.name or null
            else
              null;
          accessNodes = accessNodesForTenant tenant;
          coreHasTenant =
            core:
            core != null
            && builtins.hasAttr core nodes
            && builtins.elem tenant (tenantAttachments nodes.${core});
        in
        if tenant == null then
          [ ]
        else
          lib.concatMap (
            core:
            if coreHasTenant core then
              map (access: [
                core
                access
              ]) accessNodes
            else
              [ ]
          ) cores;
    in
    lib.unique (lib.concatMap linkForOverlay overlays);
}
