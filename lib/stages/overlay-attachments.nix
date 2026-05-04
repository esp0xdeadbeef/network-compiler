{ lib }:

siteKey: nodes: normalizedRelations: overlays:

let
  nodeNames = lib.sort builtins.lessThan (builtins.attrNames nodes);

  nodesByRole =
    role:
    lib.filter (name: (nodes.${name}.role or null) == role) nodeNames;

  firstRole =
    role:
    let
      names = nodesByRole role;
    in
    if names == [ ] then null else builtins.head names;

  tenantAccessNodes =
    tenant:
    lib.filter (
      name:
      builtins.any (
        attachment: (attachment.kind or null) == "tenant" && (attachment.name or null) == tenant
      ) (nodes.${name}.attachments or [ ])
    ) (nodesByRole "access");

  relationAllowsOverlay =
    overlayName: relation:
    (relation.action or null) == "allow"
    && builtins.isAttrs relation.to
    && (relation.to.kind or null) == "external"
    && (relation.to.name or null) == overlayName;

  relationTenants =
    relation:
    if !builtins.isAttrs relation.from then
      [ ]
    else if (relation.from.kind or null) == "tenant" then
      [ relation.from.name ]
    else if (relation.from.kind or null) == "tenant-set" then
      relation.from.members or [ ]
    else
      [ ];

  overlayAccessNodes =
    overlayName:
    lib.unique (
      lib.concatMap (
        relation: lib.concatMap tenantAccessNodes (relationTenants relation)
      ) (lib.filter (relationAllowsOverlay overlayName) normalizedRelations)
    );

  nonOverlayCoreFor =
    overlay:
    let
      candidates = lib.filter (name: name != overlay.terminateOn) (nodesByRole "core");
    in
    if candidates == [ ] then overlay.terminateOn else builtins.head candidates;

  buildOne =
    overlay:
    let
      accessNodes = overlayAccessNodes overlay.name;
      accessNode = if accessNodes == [ ] then firstRole "access" else builtins.head accessNodes;
      upstream = firstRole "upstream-selector";
      policy = firstRole "policy";
      downstream = firstRole "downstream-selector";
      ingressCore = nonOverlayCoreFor overlay;
    in
    {
      name = overlay.name;
      value = {
        attachAfterStage = "access";
        accessNodes = accessNodes;
        canonicalPath = [
          ingressCore
          upstream
          policy
          downstream
          accessNode
          "overlay:${overlay.name}"
        ];
        site = siteKey;
        terminatesOn = [ overlay.terminateOn ];
      };
    };

in
builtins.listToAttrs (map buildOne overlays)
