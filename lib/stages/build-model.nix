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
  validateServiceProviders = import ./validate-service-providers.nix { inherit lib; };

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

  communicationContractDeclared = if _hasCommunicationContract then communicationContract0 else { };

  _noLegacyExternalPolicy = validateNoLegacyExternalPolicy siteKey declared;
  _addrSafe = validateSite siteKey declared;
  _topoValid = validateTopology siteKey topo;

  nodes = topo.nodes or { };
  nodeNamesSorted = lib.sort builtins.lessThan (builtins.attrNames nodes);

  coreNodes = lib.filter (n: (nodes.${n}.role or null) == "core") nodeNamesSorted;

  overlays = normalizeTransportOverlays siteKey topo declared;
  overlayNames = lib.sort builtins.lessThan (lib.unique (map (o: o.name) overlays));

  coreUplinks = builtins.listToAttrs (
    map (n: {
      name = n;
      value =
        let
          us = normalizeUplinksForNode siteKey n (nodes.${n}.uplinks or null);

          _required = ensure (builtins.length us > 0) {
            code = "E_CORE_UPLINKS_REQUIRED";
            site = siteKey;
            path = [
              "topology"
              "nodes"
              n
              "uplinks"
            ];
            message = "core node '${n}' must define at least one uplink";
            hints = [
              "Set topology.nodes.${n}.uplinks = { uplink0 = { ipv4 = [\"0.0.0.0/0\"]; ipv6 = [\"::/0\"]; }; }."
            ];
          };
        in
        if _required then us else us;
    }) coreNodes
  );

  uplinkNames = lib.sort builtins.lessThan (
    lib.unique (lib.concatMap (n: map (u: u.name) (coreUplinks.${n} or [ ])) coreNodes)
  );

  tenants0 = if semantic ? segments && semantic.segments ? tenants then semantic.segments.tenants else [ ];

  tenants = lib.sort (a: b: a.name < b.name) tenants0;

  tenantNames = map (t: t.name) tenants;
  _uniqTenants = assertUnique "tenant name" tenantNames;

  trafficTypeIndex = buildTrafficTypeIndex communicationContractDeclared;
  serviceIndex = buildServiceIndex communicationContractDeclared;

  trafficTypeNames = builtins.attrNames trafficTypeIndex;
  serviceNames = builtins.attrNames serviceIndex;

  _uniqTrafficTypes = assertUnique "traffic type name" trafficTypeNames;
  _uniqServices = assertUnique "service name" serviceNames;
  relations0 = communicationContractDeclared.relations or [ ];
  _serviceProvidersLocal = validateServiceProviders siteKey serviceIndex semantic relations0;

  normalizedRelations0 = lib.imap0 (
    idx: r:
    normalizeRelationWithProvenance siteKey overlayNames uplinkNames tenantNames serviceIndex trafficTypeIndex idx r
  ) relations0;

  normalizedRelationIds = map (r: r.source.id) normalizedRelations0;
  _uniqRelationIds = assertUnique "relation id" normalizedRelationIds;

  normalizedRelations = sortRelations normalizedRelations0;
  overlayAttachments = buildOverlayAttachments siteKey nodes serviceIndex semantic.hosts normalizedRelations overlays;
  trafficPaths = buildTrafficPaths siteKey nodes coreUplinks serviceIndex semantic.hosts normalizedRelations;

  _noConflictingRelations = ensureNoConflictingRelations siteKey normalizedRelations;
  _hasExternalAllow = ensureHasExternalAllow siteKey normalizedRelations;

  _overlayModelExplicit = validateOverlayModel siteKey trafficTypeIndex normalizedRelations overlays;

  compiledServices = map (
    name:
    let
      svc = serviceIndex.${name};
    in
    {
      name = svc.name;
      trafficType = svc.trafficType or "any";
    }
  ) (lib.sort builtins.lessThan serviceNames);

  model = {
    tenants = tenants;
    services = compiledServices;
    relations = normalizedRelations;
    overlayAttachments = overlayAttachments;
    trafficPaths = trafficPaths;
    hostNatIngress = topo.hostNatIngress or { };
  };

  _forced = builtins.deepSeq {
    inherit
      _hasCommunicationContract
      _noLegacyExternalPolicy
      _addrSafe
      _topoValid
      _uniqTrafficTypes
      _uniqServices
      _serviceProvidersLocal
      _uniqTenants
      _uniqRelationIds
      _noConflictingRelations
      _hasExternalAllow
      _overlayModelExplicit
      ;
    tenants = tenants;
    services = compiledServices;
    relations = normalizedRelations;
    overlayAttachments = overlayAttachments;
    trafficPaths = trafficPaths;
    hostNatIngress = topo.hostNatIngress or { };
  } true;

in
builtins.seq _forced model
