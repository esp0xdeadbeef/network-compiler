{ lib }:

{ siteKey
, nodes
, throwError
,
}:

let
  accessRoleNodes = lib.filter (name: (nodes.${name}.role or null) == "access") (
    lib.sort builtins.lessThan (builtins.attrNames nodes)
  );

  hasTenantAttachment =
    name:
    builtins.any
      (
        attachment:
        builtins.isAttrs attachment
        && (attachment.kind or null) == "tenant"
        && builtins.isString (attachment.name or null)
        && attachment.name != ""
      )
      (nodes.${name}.attachments or [ ]);

  tenantAttachedAccessNodes = lib.filter hasTenantAttachment accessRoleNodes;
  accessWithoutTenantAttachments = lib.filter (name: !(hasTenantAttachment name)) accessRoleNodes;

  sourcePathFor =
    relation:
    (relation.source.sourceAudit.sourcePath
      or [
        "communicationContract"
        "relations"
        relation.source.id
      ])
    ++ [ "to" ];
in
{
  accessNodesFor =
    relation:
    let
      sourcePath = sourcePathFor relation;
      _hasEligibleAccess =
        if tenantAttachedAccessNodes != [ ] then
          true
        else
          throwError {
            code = "E_TRAFFIC_PATH_WILDCARD_DESTINATION_EMPTY";
            site = siteKey;
            path = sourcePath;
            message = "wildcard destination relation '${relation.source.id}' has no graph-resolved eligible destination alternatives";
            hints = [
              "Add at least one access node with a modeled tenant attachment before using to = \"any\"."
              "Do not repair an empty wildcard graph from inventory interfaces or renderer fanout."
            ];
          };
      _noIneligibleAccess =
        if accessWithoutTenantAttachments == [ ] then
          true
        else
          throwError {
            code = "E_TRAFFIC_PATH_WILDCARD_DESTINATION_INELIGIBLE";
            site = siteKey;
            path = sourcePath;
            message = "wildcard destination relation '${relation.source.id}' found access nodes without modeled tenant attachments";
            hints = [
              "Wildcard destination expansion is limited to graph-resolved access nodes with modeled tenant attachments."
              "Do not derive wildcard destinations from inventory interfaces, runtime fanout, host placement, bridge names, or renderer layout."
              "Ineligible access nodes: ${builtins.concatStringsSep ", " accessWithoutTenantAttachments}"
            ];
          };
    in
    if _hasEligibleAccess && _noIneligibleAccess then tenantAttachedAccessNodes else [ ];
}
