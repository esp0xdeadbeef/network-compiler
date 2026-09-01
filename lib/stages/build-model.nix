{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  policyC = import ../correctness/policy.nix { inherit lib; };
  topoC = import ../correctness/topology.nix { inherit lib; };
  addressSafety = import ../address-safety { inherit lib; };
  normalizeUplinksForNode = import ./normalize-uplinks.nix { inherit lib; };
  normalizeTransportOverlays = import ./normalize-overlays.nix { inherit lib; };
  buildOverlayAttachments = import ./overlay-attachments.nix { inherit lib; };
  validateOverlayModel = import ./validate-overlay-model.nix { inherit lib; };
  buildTrafficPaths = import ./traffic-paths.nix { inherit lib; };
  validateNoLegacyExternalPolicy = import ./validate-no-legacy-external.nix { inherit lib; };
  validateIntentSourceBoundary = import ./validate-intent-source-boundary.nix { inherit lib; };
  platformIndependence = import ./validate-platform-independence.nix { inherit lib; };
  validateServiceProviders = import ./validate-service-providers.nix { inherit lib; };
  buildCompiledServices = import ./compiled-services.nix { inherit lib; };
  buildIsolationDecisions = import ./isolation-decisions.nix { inherit lib; };
  buildAccessSpaceDiscovery = import ./access-space-discovery { inherit lib; };
  modelOutput = import ./build-model-output.nix { inherit lib; };
  sourceAudit = import ./source-audit.nix { inherit lib; };
  buildDnsContract = import ./dns-contract { inherit lib; };
  buildCoreUplinks = import ./core-uplinks.nix {
    inherit lib normalizeUplinksForNode;
    inherit (util) ensure;
  };
  inherit (util) assertUnique ensure;
  inherit (policyC)
    buildTrafficTypeIndex
    buildServiceIndex
    normalizeRelationWithProvenance
    sortRelations
    ensureNoConflictingRelations
    ensureHasExternalAllow
    ;
  inherit (topoC) validateTopology;
  inherit (addressSafety) validateSite;
in
siteKey: declared: semantic:
let
  topo = declared.topology or { };
  communicationContract0 = declared.communicationContract or null;
  _hasCommunicationContract =
    ensure (communicationContract0 != null && builtins.isAttrs communicationContract0)
      {
        code = "E_CONTRACT_REQUIRED";
        site = siteKey;
        path = [ "communicationContract" ];
        message = "every site must define communicationContract";
        hints = [
          "Add communicationContract = { trafficTypes = [ ]; services = [ ]; relations = [ ]; }."
        ];
      };

  communicationContractBase = if _hasCommunicationContract then communicationContract0 else { };
  _noLegacyExternalPolicy = validateNoLegacyExternalPolicy siteKey declared;
  _intentSourceBoundary = validateIntentSourceBoundary siteKey declared;
  _platformIndependentIntent = platformIndependence.validateIntent siteKey declared;
  _addrSafe = validateSite siteKey declared;
  nodes = topo.nodes or { };
  nodeNamesSorted = lib.sort builtins.lessThan (builtins.attrNames nodes);
  coreNodes = lib.filter (n: (nodes.${n}.role or null) == "core") nodeNamesSorted;
  overlays = normalizeTransportOverlays siteKey topo declared;
  _topoValid = validateTopology siteKey topo overlays;
  overlayNames = lib.sort builtins.lessThan (lib.unique (map (o: o.name) overlays));
  overlayPool =
    if builtins.isAttrs ((declared.pools or { }).overlay or null) then
      (declared.pools or { }).overlay
    else
      { };
  overlayAddressPools =
    if builtins.isAttrs (declared.overlayAddressPools or null) then
      declared.overlayAddressPools
    else if overlayPool == { } then
      { }
    else
      builtins.listToAttrs (
        map (overlayName: {
          name = overlayName;
          value = overlayPool;
        }) overlayNames
      );

  coreUplinks = buildCoreUplinks siteKey nodes coreNodes;
  normalizedTopologyNodes = lib.mapAttrs (
    nodeName: node:
    node
    // {
      uplinks = normalizeUplinksForNode.forNodeAttrs siteKey nodeName (node.uplinks or null);
    }
  ) nodes;
  uplinkNames = lib.sort builtins.lessThan (
    lib.unique (lib.concatMap (n: map (u: u.name) (coreUplinks.${n} or [ ])) coreNodes)
  );

  dns = buildDnsContract siteKey declared nodes coreUplinks;
  communicationContractDeclared = communicationContractBase // {
    services =
      (communicationContractBase.services or [ ]) ++ (dns.communicationContract.services or [ ]);
    relations =
      (communicationContractBase.relations or [ ]) ++ (dns.communicationContract.relations or [ ]);
  };

  tenants0 =
    if semantic ? segments && semantic.segments ? tenants then semantic.segments.tenants else [ ];
  tenants = lib.sort (a: b: a.name < b.name) tenants0;
  tenantNames = map (t: t.name) tenants;
  _uniqTenants = assertUnique "tenant name" tenantNames;
  trafficTypeIndex = buildTrafficTypeIndex communicationContractDeclared;
  serviceIndex = buildServiceIndex communicationContractDeclared;
  trafficTypeNames = builtins.attrNames trafficTypeIndex;
  serviceNames = builtins.attrNames serviceIndex;

  _uniqTrafficTypes = assertUnique "traffic type name" trafficTypeNames;
  _uniqServices = assertUnique "service name" serviceNames;
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
  _uniqRelationIds = assertUnique "relation id" normalizedRelationIds;

  normalizedRelations = sortRelations normalizedRelations0;
  overlayAttachments = buildOverlayAttachments siteKey nodes overlays;
  trafficPaths =
    buildTrafficPaths siteKey nodes coreUplinks serviceIndex semantic.hosts overlays
      normalizedRelations;

  _noConflictingRelations = ensureNoConflictingRelations siteKey normalizedRelations;
  _hasExternalAllow = ensureHasExternalAllow siteKey normalizedRelations;

  _overlayModelExplicit = validateOverlayModel siteKey trafficTypeIndex normalizedRelations overlays;

  compiledServices = buildCompiledServices siteKey serviceIndex serviceNames;
  isolationModel =
    buildIsolationDecisions siteKey nodes tenants semantic.hosts compiledServices
      communicationContractDeclared;
  accessSpaceDiscovery =
    buildAccessSpaceDiscovery siteKey serviceIndex communicationContractDeclared
      (declared.profileManifest or null);
in
modelOutput.build {
  inherit
    sourceAudit
    siteKey
    platformIndependence
    declared
    semantic
    topo
    tenants
    compiledServices
    isolationModel
    accessSpaceDiscovery
    normalizedRelations
    overlayAttachments
    overlayAddressPools
    trafficPaths
    normalizedTopologyNodes
    dns
    ;
  validations = {
    inherit
      _hasCommunicationContract
      _noLegacyExternalPolicy
      _intentSourceBoundary
      _platformIndependentIntent
      _addrSafe
      _topoValid
      _uniqTrafficTypes
      _uniqServices
      _bgpTrafficTypeRequired
      _serviceProvidersLocal
      _uniqTenants
      _uniqRelationIds
      _noConflictingRelations
      _hasExternalAllow
      _overlayModelExplicit
      ;
  };
}
