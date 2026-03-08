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
              path = [
                "topology"
                "nodes"
                u.name
                "uplinks"
                "ingressSubject"
                "kind"
              ];
              message = "uplink.ingressSubject.kind must be 'tenant'";
              hints = [ "Use ingressSubject = { kind = \"tenant\"; name = \"...\"; }." ];
            };

            _exists = ensure (builtins.elem subj.name tenantNames) {
              code = "E_UPLINK_INGRESS_SUBJECT_UNKNOWN_TENANT";
              site = siteKey;
              path = [
                "topology"
                "nodes"
                u.name
                "uplinks"
                "ingressSubject"
                "name"
              ];
              message = "uplink ingressSubject references unknown tenant '${subj.name}'";
              hints = [ "Declare tenant '${subj.name}' under ownership.prefixes." ];
            };
          in
          true;
    in
    builtins.all check allUplinks;

  relations0 = communicationContractDeclared.relations or [ ];
  relationIds = map (r: if r ? id then r.id else null) relations0;
  _uniqRelationIds = assertUnique "relation id" (lib.filter (x: x != null) relationIds);

  normalizedRelations0 = lib.imap0 (
    idx: r:
    normalizeRelationWithProvenance siteKey externals tenantNames serviceIndex trafficTypeIndex idx r
  ) relations0;

  normalizedRelations = sortRelations normalizedRelations0;

  _hasExternalAllow = ensureHasExternalAllow siteKey normalizedRelations;

  overlayHasExplicitAllow =
    ovName:
    builtins.any (
      r:
      (r.action or "deny") == "allow"
      && builtins.isAttrs r.to
      && (r.to.kind or null) == "external"
      && r.to.name == ovName
    ) normalizedRelations;

  _overlayPolicyRequired =
    if overlays == [ ] then
      true
    else
      builtins.all (
        ov:
        ensure (overlayHasExplicitAllow ov.name) {
          code = "E_OVERLAY_POLICY_MISSING";
          site = siteKey;
          path = [
            "transport"
            "overlays"
          ];
          message = "overlay '${ov.name}' requires explicit allow relation to external='${ov.name}'";
          hints = [
            "Add communicationContract.relations entry allowing traffic to { kind = \"external\"; name = \"${ov.name}\"; }."
          ];
        }
      ) overlays;

  localPool =
    if semantic ? addressPools && semantic.addressPools ? local then
      semantic.addressPools.local
    else
      null;

  p2pPool =
    if semantic ? addressPools && semantic.addressPools ? p2p then semantic.addressPools.p2p else null;

  allocLoopV4 = allocator.mkIPv4Allocator localPool;
  allocLoopV6 = allocator.mkIPv6Allocator localPool;

  loopbacks = lib.listToAttrs (
    lib.imap0 (idx: name: {
      name = name;
      value = {
        ipv4 = allocLoopV4 idx;
        ipv6 = allocLoopV6 idx;
      };
    }) nodeNamesSorted
  );

  allocP2pV4 = allocator.mkIPv4Allocator p2pPool;
  allocP2pV6 = allocator.mkIPv6Allocator p2pPool;

  adjacencyAddrs = lib.imap0 (
    idx: pair:
    let
      a = builtins.elemAt pair 0;
      b = builtins.elemAt pair 1;
    in
    {
      endpoints = [
        {
          unit = a;
          local = {
            ipv4 = allocP2pV4 (idx * 2);
            ipv6 = allocP2pV6 (idx * 2);
          };
        }
        {
          unit = b;
          local = {
            ipv4 = allocP2pV4 (idx * 2 + 1);
            ipv6 = allocP2pV6 (idx * 2 + 1);
          };
        }
      ];
    }
  ) links0;

  mkUnitIsolation =
    n:
    let
      role = nodes.${n}.role or null;
      isolated = builtins.elem role [
        "core"
        "access"
      ];
    in
    if isolated then
      {
        containers = [ "isolated-0" ];
        isolated = true;
      }
    else
      {
        containers = [ "default" ];
        isolated = false;
      };

  unitIsolation = lib.listToAttrs (
    map (n: {
      name = n;
      value = mkUnitIsolation n;
    }) nodeNamesSorted
  );

  compiledServices = map (
    svc:
    svc
    // {
      providers = svc.providers or [ ];
    }
  ) (communicationContractDeclared.services or [ ]);

  compiledTrafficTypes = map (
    name:
    let
      t = trafficTypeIndex.${name};
    in
    {
      inherit (t) name match;
    }
  ) (lib.sort builtins.lessThan trafficTypeNames);

  communicationContract = {
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
      adjacencies = adjacencyAddrs;
    };

    transport = {
      overlays = overlays;
    };

    addressPools = semantic.addressPools or { };

    routerLoopbacks = loopbacks;

    units = unitIsolation;

    uplinks = {
      multiWan = anyMultiWan;
      cores = coreUplinks;
    };

    inherit communicationContract;
  };

  _forced = builtins.deepSeq {
    inherit
      _hasCommunicationContract
      _noLegacyExternalPolicy
      _addrSafe
      _topoValid
      _noDisconnectedNodes
      _uniqTrafficTypes
      _uniqServices
      _uniqTenants
      _uniqHosts
      _uniqRelationIds
      _validateServiceTrafficTypes
      _validateServiceProviders
      _overlayPolicyRequired
      _validateIngressSubjects
      _hasExternalAllow
      ;
    normalizedRelations = normalizedRelations;
    coreUplinks = coreUplinks;
    overlays = overlays;
    externals = externals;
    hosts = hosts;
  } true;

in
if _forced then model else model
