{ lib }:

let
  allocator = import ../allocators/pinned-allocator.nix { inherit lib; };

  util = import ../correctness/util.nix { inherit lib; };
  policyC = import ../correctness/policy.nix { inherit lib; };
  topoC = import ../correctness/topology.nix { inherit lib; };
  addressSafety = import ../address-safety { inherit lib; };

  splitSiteKey = import ./split-site-key.nix { inherit lib; };
  normalizeUplinksForNode = import ./normalize-uplinks.nix { inherit lib; };
  normalizeTransportOverlays = import ./normalize-overlays.nix { inherit lib; };
  validateNoLegacyExternalPolicy = import ./validate-no-legacy-external.nix { inherit lib; };

  inherit (util) assertUnique ensure throwError;
  inherit (policyC)
    buildTrafficTypeIndex
    buildServiceIndex
    normalizeRelationWithProvenance
    sortRelations
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

  interfaceTags = communicationContractDeclared.interfaceTags or { };

  parts = splitSiteKey siteKey;
  canonicalSiteId = "${parts.enterprise}.${parts.siteName}";

  _noLegacyExternalPolicy = validateNoLegacyExternalPolicy siteKey declared;
  _addrSafe = validateSite siteKey declared;
  _topoValid = validateTopology siteKey topo;

  nodes = topo.nodes or { };
  nodeNamesSorted = lib.sort builtins.lessThan (builtins.attrNames nodes);

  links0 = topo.links or [ ];

  linkNodes = lib.unique (lib.concatMap (pair: pair) links0);

  _noDisconnectedNodes =
    let
      disconnected = lib.filter (n: !(builtins.elem n linkNodes)) nodeNamesSorted;
    in
    if disconnected == [ ] then
      true
    else
      throw (
        builtins.toJSON {
          code = "E_TOPOLOGY_NODE_DISCONNECTED";
          site = siteKey;
          nodes = disconnected;
          message = "nodes exist in topology.nodes but are not connected by any topology.links";
        }
      );

  coreNodes = lib.filter (n: (nodes.${n}.role or null) == "core") nodeNamesSorted;

  overlays = normalizeTransportOverlays siteKey topo declared;
  overlayNames = map (o: o.name) overlays;

  coreUplinks = lib.listToAttrs (
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
              "Set topology.nodes.${n}.uplinks = { wan = { ipv4 = [\"0.0.0.0/0\"]; ipv6 = [\"::/0\"]; }; }."
            ];
          };
        in
        if _required then us else us;
    }) coreNodes
  );

  uplinkNames = lib.unique (lib.concatMap (n: map (u: u.name) (coreUplinks.${n} or [ ])) coreNodes);
  externals = lib.unique (uplinkNames ++ overlayNames);

  totalUplinks = builtins.foldl' (
    acc: n: acc + (builtins.length (coreUplinks.${n} or [ ]))
  ) 0 coreNodes;

  anyMultiWan = totalUplinks > 1;

  tenants =
    if semantic ? segments && semantic.segments ? tenants then semantic.segments.tenants else [ ];

  tenantNames = map (t: t.name) tenants;
  _uniqTenants = assertUnique "tenant name" tenantNames;

  attachments = semantic.attachments or [ ];

  tenantAccessUnits = builtins.foldl' (
    acc: attachment:
    let
      segment = attachment.segment or "";
      m = builtins.match "tenants:(.*)" segment;
    in
    if m == null then
      acc
    else
      let
        tenantName = builtins.elemAt m 0;
        units0 = acc.${tenantName} or [ ];
      in
      acc
      // {
        "${tenantName}" = units0 ++ [ attachment.unit ];
      }
  ) { } attachments;

  normalizedHosts0 = semantic.hosts or [ ];
  hostNames = map (h: h.name) normalizedHosts0;
  _uniqHosts = assertUnique "host name" hostNames;

  resolveHostUnit =
    host:
    let
      tenant = host.tenant or null;

      _tenantPresent = ensure (tenant != null && builtins.isString tenant && tenant != "") {
        code = "E_HOST_TENANT_REQUIRED";
        site = siteKey;
        path = [
          "ownership"
          "endpoints"
          host.name or "unknown"
          "tenant"
        ];
        message = "host '${host.name or "unknown"}' must define tenant";
        hints = [ "Set ownership.endpoints[].tenant to an existing tenant name." ];
      };

      _tenantExists = ensure (builtins.elem tenant tenantNames) {
        code = "E_HOST_UNKNOWN_TENANT";
        site = siteKey;
        path = [
          "ownership"
          "endpoints"
          host.name or "unknown"
          "tenant"
        ];
        message = "host '${host.name or "unknown"}' references unknown tenant '${toString tenant}'";
        hints = [ "Declare tenant '${toString tenant}' under ownership.prefixes." ];
      };

      unitsForTenant = lib.sort builtins.lessThan (tenantAccessUnits.${tenant} or [ ]);

      _accessUnitExists = ensure (unitsForTenant != [ ]) {
        code = "E_HOST_NO_ACCESS_UNIT";
        site = siteKey;
        path = [
          "ownership"
          "endpoints"
          host.name or "unknown"
        ];
        message = "host '${host.name or "unknown"}' belongs to tenant '${tenant}' but no access unit is attached to that tenant";
        hints = [
          "Attach tenant '${tenant}' to an access node under topology.nodes.<name>.attachments."
        ];
      };
    in
    builtins.elemAt unitsForTenant 0;

  hosts = builtins.listToAttrs (
    map (
      host:
      let
        unit = resolveHostUnit host;
      in
      {
        name = host.name;
        value = {
          tenant = host.tenant;
          inherit unit;
        };
      }
    ) normalizedHosts0
  );

  trafficTypeIndex = buildTrafficTypeIndex communicationContractDeclared;
  serviceIndex = buildServiceIndex communicationContractDeclared;

  trafficTypeNames = builtins.attrNames trafficTypeIndex;
  serviceNames = builtins.attrNames serviceIndex;

  _uniqTrafficTypes = assertUnique "traffic type name" trafficTypeNames;
  _uniqServices = assertUnique "service name" serviceNames;

  _validateServiceTrafficTypes = builtins.all (
    svc:
    let
      trafficTypeName = svc.trafficType or null;
    in
    ensure
      (
        trafficTypeName != null
        && (trafficTypeName == "any" || builtins.elem trafficTypeName trafficTypeNames)
      )
      {
        code = "E_CONTRACT_UNKNOWN_TRAFFIC_TYPE";
        site = siteKey;
        path = [
          "communicationContract"
          "services"
          svc.name or "unknown"
          "trafficType"
        ];
        message = "service '${svc.name or "unknown"}' references unknown trafficType '${toString trafficTypeName}'";
        hints = [ "Declare the traffic type under communicationContract.trafficTypes." ];
      }
  ) (communicationContractDeclared.services or [ ]);

  _validateServiceProviders = builtins.all (
    svc:
    let
      providers = svc.providers or [ ];
    in
    builtins.all (
      provider:
      ensure (builtins.hasAttr provider hosts) {
        code = "E_CONTRACT_UNKNOWN_PROVIDER_HOST";
        site = siteKey;
        path = [
          "communicationContract"
          "services"
          svc.name or "unknown"
          "providers"
        ];
        message = "service '${svc.name or "unknown"}' references unknown provider host '${provider}'";
        hints = [ "Declare the host under ownership.endpoints." ];
      }
    ) providers
  ) (communicationContractDeclared.services or [ ]);

  _validateIngressSubjects =
    let
      allUplinks = lib.concatMap (n: coreUplinks.${n} or [ ]) coreNodes;

      check =
        u:
        let
          subj = u.ingressSubject or null;
        in
        if subj == null then
          true
        else
          let
            _kind = ensure ((subj.kind or null) == "tenant") {
              code = "E_UPLINK_INGRESS_SUBJECT_KIND";
              site = siteKey;
            };

            _exists = ensure (builtins.elem subj.name tenantNames) {
              code = "E_UPLINK_INGRESS_SUBJECT_UNKNOWN_TENANT";
              site = siteKey;
            };
          in
          true;
    in
    builtins.all check allUplinks;

  relations0 = communicationContractDeclared.relations or [ ];

  normalizedRelations = sortRelations (
    lib.imap0 (
      idx: r:
      normalizeRelationWithProvenance siteKey externals tenantNames serviceIndex trafficTypeIndex idx r
    ) relations0
  );

  _hasExternalAllow = ensureHasExternalAllow siteKey normalizedRelations;

  compiledServices = map (svc: svc // { providers = svc.providers or [ ]; }) (
    communicationContractDeclared.services or [ ]
  );

  compiledTrafficTypes = map (
    name:
    let
      t = trafficTypeIndex.${name};
    in
    {
      inherit (t) name match;
    }
  ) (lib.sort builtins.lessThan trafficTypeNames);

  communicationContract =
    (builtins.removeAttrs communicationContractDeclared [
      "relations"
      "services"
      "trafficTypes"
    ])
    // {
      interfaceTags = interfaceTags;
      trafficTypes = compiledTrafficTypes;
      services = compiledServices;
      allowedRelations = normalizedRelations;
    };

  model = {
    id = canonicalSiteId;
    enterprise = semantic.enterprise or "default";

    domains = {
      tenants = tenants;
    };
    hosts = hosts;
    attachment = semantic.attachments or [ ];

    transit = {
      ordering = links0;
      adjacencies = [ ];
    };

    transport = {
      overlays = overlays;
    };
    addressPools = semantic.addressPools or { };

    routerLoopbacks = { };
    units = { };

    uplinks = {
      multiWan = anyMultiWan;
      cores = coreUplinks;
    };

    inherit communicationContract;
  };

in
model
