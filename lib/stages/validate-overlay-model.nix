{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;

  relationEndpointIsOverlay =
    overlayName: endpoint:
    builtins.isAttrs endpoint
    && (endpoint.kind or null) == "external"
    && (endpoint.name or null) == overlayName;

  relationAllowsOverlayUnderlay =
    overlayName: trafficTypeIndex: relation:
    let
      trafficType = relation.trafficType or null;
    in
    (relation.action or null) == "allow"
    && relationEndpointIsOverlay overlayName relation.from
    && builtins.isString trafficType
    && trafficType != ""
    && trafficType != "any"
    && builtins.hasAttr trafficType trafficTypeIndex
    && builtins.isAttrs relation.to
    && (
      (relation.to.kind or null) == "service"
      || (relation.to.kind or null) == "external"
    );

  externalNames =
    endpoint:
    if !(builtins.isAttrs endpoint) || (endpoint.kind or null) != "external" then
      [ ]
    else if endpoint ? uplinks then
      endpoint.uplinks
    else if endpoint ? name then
      [ endpoint.name ]
    else
      [ ];

  endpointTenants =
    endpoint:
    if !(builtins.isAttrs endpoint) then
      [ ]
    else if (endpoint.kind or null) == "tenant" then
      [ endpoint.name ]
    else if (endpoint.kind or null) == "tenant-set" then
      endpoint.members or [ ]
    else
      [ ];

  trafficCompatible =
    wanted: candidate:
    let
      actual = candidate.trafficType or null;
    in
    actual == "any" || actual == wanted;

  relationAllowsUnderlayTenantEgress =
    tenantName: targetExternalNames: underlayTrafficType: relation:
    (relation.action or null) == "allow"
    && builtins.elem tenantName (endpointTenants relation.from)
    && builtins.any (name: builtins.elem name targetExternalNames) (externalNames relation.to)
    && trafficCompatible underlayTrafficType relation;

  relationReferencesOverlay =
    overlayName: relation:
    (
      builtins.isAttrs (relation.to or null)
      && (relation.to.kind or null) == "external"
      && (relation.to.name or null) == overlayName
    )
    || (
      builtins.isAttrs (relation.from or null)
      && (relation.from.kind or null) == "external"
      && (relation.from.name or null) == overlayName
    );

  validateOne =
    siteKey: trafficTypeIndex: normalizedRelations: overlay:
    let
      overlayName = overlay.name;
      _referenced = ensure (builtins.any (relationReferencesOverlay overlayName) normalizedRelations) {
        code = "E_OVERLAY_DEFINED_WITHOUT_POLICY_RULES";
        site = siteKey;
        path = [
          "transport"
          "overlays"
        ];
        message = "overlay '${overlayName}' is defined but has no communicationContract relation";
        hints = [ "Add a relation that references external '${overlayName}'." ];
      };

      hasUnderlayRelation =
        builtins.any (relationAllowsOverlayUnderlay overlayName trafficTypeIndex) normalizedRelations;

      _hasUnderlayRelation = ensure (_referenced && hasUnderlayRelation) {
        code = "E_OVERLAY_UNDERLAY_RELATION_REQUIRED";
        site = siteKey;
        path = [
          "communicationContract"
          "relations"
        ];
        message = "overlay '${overlayName}' must have an explicit underlay/control allow relation";
        hints = [
          "Add an allow relation from external '${overlayName}' with a concrete non-any trafficType."
          "Use a service relation when a local DMZ lighthouse/listener owns the socket and port."
          "Use an external/uplink relation when the overlay daemon reaches a remote listener through WAN."
          "The service or traffic type defines the actual port, for example UDP 80, UDP 4242, or UDP 51820."
          "Do not rely on compiler or renderer name inference from overlay-specific node names."
        ];
      };

      underlayAccess = overlay.underlayAccess or { };
      underlayAccessTenant =
        if (underlayAccess.kind or null) == "tenant" then underlayAccess.name or null else null;

      underlayExternalRelations =
        lib.filter
          (relation:
            relationAllowsOverlayUnderlay overlayName trafficTypeIndex relation
            && builtins.isAttrs (relation.to or null)
            && (relation.to.kind or null) == "external")
          normalizedRelations;

      _underlayTenantHasWanEgress =
        lib.forEach underlayExternalRelations (
          relation:
          let
            targetNames = externalNames relation.to;
            ok =
              underlayAccessTenant != null
              && builtins.any
                (candidate:
                  relationAllowsUnderlayTenantEgress underlayAccessTenant targetNames (relation.trafficType or null) candidate)
                normalizedRelations;
          in
          ensure ok {
            code = "E_OVERLAY_UNDERLAY_ACCESS_WAN_EGRESS_REQUIRED";
            site = siteKey;
            path = [
              "transport"
              "overlays"
              overlayName
              "underlayAccess"
            ];
            message = "overlay '${overlayName}' underlayAccess tenant '${toString underlayAccessTenant}' has no allowed egress relation to the underlay target external";
            hints = [
              "Select a real access tenant that already has modeled WAN/default egress to the target external."
              "Do not select an overlay-payload tenant such as hostile when that tenant's public egress depends on the overlay being bootstrapped."
              "If the underlay daemon should live on the client LAN, set underlayAccess to that client tenant and keep the normal client-to-WAN allow relation."
            ];
          }
        );
    in
    builtins.deepSeq
      {
        inherit _referenced _hasUnderlayRelation _underlayTenantHasWanEgress;
      }
      true;

in
siteKey: trafficTypeIndex: normalizedRelations: overlays:
if overlays == [ ] then
  true
else
  builtins.all (idx: validateOne siteKey trafficTypeIndex normalizedRelations (builtins.elemAt overlays idx)) (
    lib.range 0 ((builtins.length overlays) - 1)
  )
