{
  lib,
  assertUnique,
  policyC,
  validateOverlayModel,
  validateServiceProviders,
  buildOverlayAttachments,
  buildTrafficPaths,
  buildCompiledServices,
  buildIsolationDecisions,
  buildAccessSpaceDiscovery,
}:

let
  inherit (policyC)
    normalizeRelationWithProvenance
    sortRelations
    ensureNoConflictingRelations
    ensureHasExternalAllow
    ;
in
{

  prepare =
    siteKey: declared: semantic: fabric: contracts:
    let
      inherit (fabric)
        nodes
        normalizedTopologyNodes
        overlayNames
        uplinkNames
        ;
      scopeNames = lib.sort builtins.lessThan (builtins.attrNames nodes);
      inherit (contracts)
        communicationContractDeclared
        serviceIndex
        serviceNames
        tenantNames
        trafficTypeIndex
        ;
      inherit (contracts) tenants;

      bgpBoundaries = lib.concatMap (
        nodeName:
        lib.optional (builtins.elem "bgp" (normalizedTopologyNodes.${nodeName}.behaviors or [ ])) nodeName
      ) (builtins.attrNames normalizedTopologyNodes);
      _bgpTrafficTypeRequired =
        bgpBoundaries == [ ]
        || builtins.any (t: (t.name or null) == "bgp") (communicationContractDeclared.trafficTypes or [ ])
        || throw "intent communicationContract.trafficTypes must declare a 'bgp' traffic type (tcp/179) when an uplink egress selects bgp routing (${builtins.concatStringsSep ", " bgpBoundaries})";

      livenessBoundaries = lib.concatMap (
        nodeName:
        lib.optional (builtins.elem "liveness" (
          normalizedTopologyNodes.${nodeName}.behaviors or [ ]
        )) nodeName
      ) (builtins.attrNames normalizedTopologyNodes);
      hasLivenessTrafficType = builtins.any (
        t:
        builtins.elem (t.name or null) [
          "liveness"
          "bfd"
        ]
      ) (communicationContractDeclared.trafficTypes or [ ]);
      _livenessTrafficTypeRequired =
        livenessBoundaries == [ ]
        || hasLivenessTrafficType
        || throw "FS-483-HDS-010-SDS-010-SMS-010: intent communicationContract.trafficTypes must declare a 'liveness' (or 'bfd') control-plane traffic type when a scope requires the liveness behavior (${builtins.concatStringsSep ", " livenessBoundaries})";

      relations0 = communicationContractDeclared.relations or [ ];
      _serviceProvidersLocal = validateServiceProviders siteKey serviceIndex semantic nodes relations0;

      normalizedRelations0 = lib.imap0 (
        idx: r:
        normalizeRelationWithProvenance siteKey overlayNames uplinkNames scopeNames tenantNames serviceIndex
          trafficTypeIndex
          idx
          r
      ) relations0;

      normalizedRelationIds = map (r: r.source.id) normalizedRelations0;
      normalizedRelations = sortRelations normalizedRelations0;
      overlayAttachments = buildOverlayAttachments siteKey nodes fabric.overlays;
      trafficPaths =
        buildTrafficPaths siteKey nodes fabric.coreUplinks serviceIndex semantic.hosts fabric.overlays
          normalizedRelations;

      _noConflictingRelations = ensureNoConflictingRelations siteKey normalizedRelations;
      _hasExternalAllow = ensureHasExternalAllow siteKey normalizedRelations;
      _overlayModelExplicit =
        validateOverlayModel siteKey trafficTypeIndex normalizedRelations fabric.overlays
          normalizedTopologyNodes;

      compiledServices = buildCompiledServices siteKey serviceIndex (builtins.attrNames serviceIndex);
      isolationModel =
        buildIsolationDecisions siteKey nodes tenants semantic.hosts compiledServices
          communicationContractDeclared;
      accessSpaceDiscovery =
        buildAccessSpaceDiscovery siteKey serviceIndex communicationContractDeclared
          (declared.profileManifest or null);
    in
    {
      inherit
        normalizedRelations
        overlayAttachments
        trafficPaths
        compiledServices
        isolationModel
        accessSpaceDiscovery
        ;
      validations = {
        inherit
          _bgpTrafficTypeRequired
          _livenessTrafficTypeRequired
          _serviceProvidersLocal
          _noConflictingRelations
          _hasExternalAllow
          _overlayModelExplicit
          ;
        _uniqRelationIds = assertUnique "relation id" normalizedRelationIds;
      };
    };
}
