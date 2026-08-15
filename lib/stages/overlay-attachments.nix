{ lib }:

siteKey: nodes: overlays:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) throwError;

  nodeNames = lib.sort builtins.lessThan (builtins.attrNames nodes);

  nodesByRole = role: lib.filter (name: (nodes.${name}.role or null) == role) nodeNames;

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

  overlayAccessNodes =
    overlay:
    let
      selector = overlay.underlayAccess or null;
    in
    if !builtins.isAttrs selector then
      throwError {
        code = "E_OVERLAY_UNDERLAY_ACCESS_REQUIRED";
        site = siteKey;
        path = [
          "transport"
          "overlays"
          overlay.name
          "underlayAccess"
        ];
        message = "overlay '${overlay.name}' requires an explicit underlay access selector";
        hints = [
          "Set transport.overlays[].underlayAccess to the tenant-backed access router used by the overlay daemon/control WAN side."
          "Do not derive underlay attachment from payload tenants that are allowed to use the overlay, such as hostile."
        ];
      }
    else if (selector.kind or null) == "tenant" then
      tenantAccessNodes selector.name
    else
      throwError {
        code = "E_OVERLAY_UNDERLAY_ACCESS_UNSUPPORTED";
        site = siteKey;
        path = [
          "transport"
          "overlays"
          overlay.name
          "underlayAccess"
        ];
        message = "overlay '${overlay.name}' underlayAccess must currently select a tenant access attachment";
        hints = [
          "Use underlayAccess = { kind = \"tenant\"; name = \"client\"; } or another explicitly modeled access tenant with WAN reachability."
        ];
      };

  nonOverlayCoreFor =
    overlay:
    let
      overlayCores = overlay.terminateOn or [ ];
      candidates = lib.filter (name: !(builtins.elem name overlayCores)) (nodesByRole "core");
    in
    if candidates == [ ] then null else builtins.head candidates;

  buildOne =
    overlay:
    let
      accessNodes = overlayAccessNodes overlay;
      accessNode =
        if accessNodes == [ ] then
          throwError {
            code = "E_OVERLAY_ACCESS_ATTACHMENT_REQUIRED";
            site = siteKey;
            path = [
              "communicationContract"
              "relations"
            ];
            message = "overlay '${overlay.name}' underlayAccess does not resolve to any access node";
            hints = [
              "Add a topology access node attached to transport.overlays[].underlayAccess."
              "Do not rely on compiler, forwarding-model, control-plane, or renderer fallback to pick an access node from payload policy."
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
        terminatesOn = overlay.terminateOn;
      };
    };

in
builtins.listToAttrs (map buildOne overlays)
