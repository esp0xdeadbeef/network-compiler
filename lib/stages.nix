{ lib }:

let
  flattenSites = import ./flatten-sites.nix { inherit lib; };
  normalizeSite = import ./normalize/from-user-input.nix { inherit lib; };
  allocator = import ./allocators/pinned-allocator.nix { inherit lib; };

  util = import ./correctness/util.nix { inherit lib; };
  policyC = import ./correctness/policy.nix { inherit lib; };
  topoC = import ./correctness/topology.nix { inherit lib; };
  addressSafety = import ./address-safety { inherit lib; };
  canonicalize = import ./canonicalize.nix { inherit lib; };

  inherit (util) assertUnique ensure throwError;
  inherit (policyC)
    buildCapabilityIndex
    normalizeRuleWithProvenance
    sortRules
    normalizeNatIngress
    ;
  inherit (topoC) validateTopology;
  inherit (addressSafety) validateSite;

  splitSiteKey =
    key:
    let
      m = builtins.match "([^.]*)\\.(.*)" key;
    in
    if m == null then
      {
        enterprise = "default";
        siteName = key;
      }
    else
      {
        enterprise = builtins.elemAt m 0;
        siteName = builtins.elemAt m 1;
      };

  regroupSites =
    compiledFlat:
    let
      keys = lib.sort builtins.lessThan (builtins.attrNames compiledFlat);

      addOne =
        acc: k:
        let
          parts = splitSiteKey k;
          ent = parts.enterprise;
          sname = parts.siteName;

          ent0 = acc.${ent} or { };
          siteVal = compiledFlat.${k};
        in
        acc
        // {
          "${ent}" = ent0 // {
            "${sname}" = siteVal;
          };
        };
    in
    builtins.foldl' addOne { } keys;

  buildModel =
    siteKey: declared: semantic:
    let
      topo = declared.topology or { };
      policy = declared.policy or { };

      parts = splitSiteKey siteKey;
      canonicalSiteId = "${parts.enterprise}.${parts.siteName}";

      _addrSafe = validateSite siteKey declared;
      _topoValid = validateTopology siteKey topo;

      catalog = policy.catalog or { };
      services = catalog.services or [ ];
      serviceNames = map (s: s.name) services;
      _uniqServices = assertUnique "service name" serviceNames;

      tenants =
        if semantic ? segments && semantic.segments ? tenants then semantic.segments.tenants else [ ];

      tenantNames = map (t: t.name) tenants;
      _uniqTenants = assertUnique "tenant name" tenantNames;

      capIndex = buildCapabilityIndex policy;

      rules0 = policy.rules or [ ];
      ruleIds = map (r: if r ? id then r.id else null) rules0;
      _uniqRuleIds = assertUnique "rule id" (lib.filter (x: x != null) ruleIds);

      normalizedRules0 = lib.imap0 (
        idx: r: normalizeRuleWithProvenance tenantNames capIndex idx r
      ) rules0;

      normalizedRules = sortRules normalizedRules0;

      ingressExpanded = normalizeNatIngress policy;

      nodes = topo.nodes or { };
      nodeNamesSorted = lib.sort builtins.lessThan (builtins.attrNames nodes);

      coreNodes = lib.filter (n: (nodes.${n}.role or null) == "core") nodeNamesSorted;

      coreNatMode =
        n:
        let
          nat = nodes.${n}.nat or null;
          mode = if nat == null then null else nat.mode or null;

          _present = ensure (mode != null) {
            code = "E_NAT_CORE_MODE_MISSING";
            site = siteKey;
            path = [
              "topology"
              "nodes"
              n
              "nat"
              "mode"
            ];
            message = "core node '${n}' in site '${siteKey}' must explicitly declare node.nat.mode";
            hints = [ "Set topology.nodes.${n}.nat.mode = \"none\" or \"custom\"." ];
          };

          _valid =
            ensure
              (builtins.elem mode [
                "none"
                "custom"
              ])
              {
                code = "E_NAT_CORE_MODE_INVALID";
                site = siteKey;
                path = [
                  "topology"
                  "nodes"
                  n
                  "nat"
                  "mode"
                ];
                message = "core node '${n}' in site '${siteKey}' has invalid node.nat.mode '${toString mode}'";
                hints = [ "Valid values: \"none\" or \"custom\"." ];
              };
        in
        mode;

      coreModes = map coreNatMode coreNodes;

      _natRequiresCustomCore =
        ensure (!(builtins.length ingressExpanded > 0) || (builtins.elem "custom" coreModes))
          {
            code = "E_NAT_INGRESS_REQUIRES_CUSTOM_CORE";
            site = siteKey;
            path = [
              "policy"
              "nat"
              "ingress"
            ];
            message = "policy.nat.ingress is non-empty for site '${siteKey}', but no core node has node.nat.mode = \"custom\"";
            hints = [
              "Set at least one core node nat.mode = \"custom\"."
              "Or remove policy.nat.ingress entries if NAT is not desired."
            ];
          };

      communicationContract = {
        allowedRelations = normalizedRules;
        nat = {
          ingress = ingressExpanded;
        };
      };

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

      links0 = topo.links or [ ];

      adjacencyAddrs = lib.imap0 (
        idx: pair:
        let
          a = builtins.elemAt pair 0;
          b = builtins.elemAt pair 1;

          a4 = allocP2pV4 (idx * 2);
          b4 = allocP2pV4 (idx * 2 + 1);

          a6 = allocP2pV6 (idx * 2);
          b6 = allocP2pV6 (idx * 2 + 1);
        in
        {
          endpoints = [
            {
              unit = a;
              local = {
                ipv4 = a4;
                ipv6 = a6;
              };
            }
            {
              unit = b;
              local = {
                ipv4 = b4;
                ipv6 = b6;
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

      model = {

        inputs = declared;

        id = canonicalSiteId;
        enterprise = semantic.enterprise or "default";

        domains = {
          tenants = tenants;
        };

        attachment = semantic.attachments or [ ];

        transit = {
          ordering = links0;
          adjacencies = adjacencyAddrs;
        };

        addressPools = semantic.addressPools or { };

        routerLoopbacks = loopbacks;

        units = unitIsolation;

        inherit communicationContract;
      };

      _forced = builtins.deepSeq {
        inherit
          _addrSafe
          _topoValid
          _uniqServices
          _uniqTenants
          _uniqRuleIds
          _natRequiresCustomCore
          ;
        normalizedRules = normalizedRules;
        ingressExpanded = ingressExpanded;
        coreModes = coreModes;
      } true;
    in
    if _forced then model else model;

  compileSite =
    siteKey: declared:
    let
      semantic = normalizeSite declared;
    in
    buildModel siteKey declared semantic;

in
{
  run =
    inputs:
    let
      sitesFlat = flattenSites inputs;
      compiledFlat = lib.mapAttrs compileSite sitesFlat;
      compiledGrouped = regroupSites compiledFlat;

      out = {
        sites = compiledGrouped;
        meta = {
          schemaVersion = 2;
        };
      };
    in
    canonicalize out;
}
