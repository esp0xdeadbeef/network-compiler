{ lib }:

siteKey: nodes: serviceIndex: hosts: normalizedRelations: overlays:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) throwError;

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
    else if (relation.from.kind or null) == "service" then
      let
        service = serviceIndex.${relation.from.name} or null;
        providers =
          if service != null && builtins.isList (service.providers or null) then
            service.providers
          else
            [ ];
        hostTenant =
          providerName:
          let
            matches = lib.filter (
              host:
              builtins.isAttrs host
              && toString (host.name or "") == toString providerName
              && (host.tenant or null) != null
            ) hosts;
          in
          if matches == [ ] then null else toString ((builtins.head matches).tenant);
      in
      lib.unique (lib.filter (tenant: tenant != null) (map hostTenant providers))
    else
      [ ];

  overlayHasAccessRelation =
    overlayName: builtins.any (relationAllowsOverlay overlayName) normalizedRelations;

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
      accessNode =
        if accessNodes == [ ] then
          throwError {
            code = "E_OVERLAY_ACCESS_ATTACHMENT_REQUIRED";
            site = siteKey;
            path = [
              "communicationContract"
              "relations"
            ];
            message = "overlay '${overlay.name}' requires an explicit tenant allow relation to own the access attachment";
            hints = [
              "Add an allow relation from a tenant or tenant-set to external '${overlay.name}'."
              "Do not rely on compiler, forwarding-model, control-plane, or renderer fallback to pick an access node."
            ];
          }
        else
          builtins.head accessNodes;
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
builtins.listToAttrs (
  map buildOne (lib.filter (overlay: overlayHasAccessRelation overlay.name) overlays)
)
