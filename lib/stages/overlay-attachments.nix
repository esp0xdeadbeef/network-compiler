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

      canonicalPath = [
        ingressCore
        upstream
        policy
        downstream
        accessNode
        "overlay:${overlay.name}"
      ];
      mustTraverse = overlay.mustTraverse or [ ];
      # mustTraverse is a STAGE assertion authored in intent, so its entries are
      # stage roles ("policy"), while canonicalPath carries concrete node names
      # ("s-router-policy"). Comparing the raw strings made the assertion always
      # fire on satisfied input, which is why it was never forced. Resolve each
      # entry to the canonical node that realises the named stage, accepting
      # either the stage role or the node name of a node with that role.
      stageRoleOf =
        name:
        if builtins.isString name && builtins.isAttrs (nodes.${name} or null) then
          nodes.${name}.role or null
        else
          null;
      canonicalStages = map stageRoleOf canonicalPath;
      resolvesToStage =
        stage:
        builtins.elem stage canonicalStages
        || builtins.elem stage canonicalPath
        || builtins.any (
          n:
          builtins.isString n
          && (if builtins.isAttrs (nodes.${n} or null) then nodes.${n}.role or null else null) == stage
        ) canonicalPath;
      unsupportedMustTraverse = lib.filter (s: !(resolvesToStage s)) mustTraverse;
      _mustTraverseSatisfied =
        unsupportedMustTraverse == [ ]
        || throwError {
          code = "E_OVERLAY_MUST_TRAVERSE_UNSATISFIED";
          site = siteKey;
          path = [
            "transport"
            "overlays"
            overlay.name
            "mustTraverse"
          ];
          message = "overlay '${overlay.name}' mustTraverse names stage(s) not present in the derived canonical path: ${lib.concatStringsSep ", " unsupportedMustTraverse}";
          hints = [
            "mustTraverse asserts which stages the derived overlay path crosses; it does not author the path."
            "Remove stages the canonical fabric does not traverse, or model the topology so they are traversed."
          ];
        };
    in
    {
      name = overlay.name;
      value =
        # mustTraverse is an assertion, not a path input: a named stage the
        # derived canonical path does not traverse must fail closed here rather
        # than being silently ignored. Force it before the attachment is
        # published so no consumer can observe an unsatisfied assertion.
        builtins.seq _mustTraverseSatisfied {
          attachAfterStage = "access";
          accessNodes = accessNodes;
          inherit
            canonicalPath
            mustTraverse
            ;
          site = siteKey;
          terminatesOn = overlay.terminateOn;
        };
    };

in
builtins.listToAttrs (map buildOne overlays)
