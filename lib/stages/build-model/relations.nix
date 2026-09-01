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
        lib.concatMap (
          uplink:
          lib.optional (((uplink.egress or { }).mode or "static") == "bgp") "${nodeName}.${uplink.name}"
        ) (builtins.attrValues (normalizedTopologyNodes.${nodeName}.uplinks or { }))
      ) (builtins.attrNames normalizedTopologyNodes);
      _bgpTrafficTypeRequired =
        bgpBoundaries == [ ]
        || builtins.any (t: (t.name or null) == "bgp") (communicationContractDeclared.trafficTypes or [ ])
        || throw "intent communicationContract.trafficTypes must declare a 'bgp' traffic type (tcp/179) when an uplink egress selects bgp routing (${builtins.concatStringsSep ", " bgpBoundaries})";

      relations0 = communicationContractDeclared.relations or [ ];
      _serviceProvidersLocal = validateServiceProviders siteKey serviceIndex semantic nodes relations0;

      normalizedRelations0 = lib.imap0 (
        idx: r:
        normalizeRelationWithProvenance siteKey overlayNames uplinkNames tenantNames serviceIndex
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
        validateOverlayModel siteKey trafficTypeIndex normalizedRelations
          fabric.overlays;

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
          _serviceProvidersLocal
          _noConflictingRelations
          _hasExternalAllow
          _overlayModelExplicit
          ;
        _uniqRelationIds = assertUnique "relation id" normalizedRelationIds;
      };
    };
}
