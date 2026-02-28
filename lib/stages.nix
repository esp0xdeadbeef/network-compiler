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

  normalizeUpstreams =
    u:
    if u == null then
      [ ]
    else if builtins.isAttrs u then
      map (k: { name = k; }) (lib.sort builtins.lessThan (builtins.attrNames u))
    else
      [ ];

  normalizeTransportOverlays =
    siteKey: topo: declared:
    let
      nodes = topo.nodes or { };
      nodeNames = builtins.attrNames nodes;

      coreNodes = lib.filter (n: (nodes.${n}.role or null) == "core") (
        lib.sort builtins.lessThan nodeNames
      );

      transport0 = declared.transport or { };
      overlays0 = transport0.overlays or [ ];

      _shape = ensure (builtins.isList overlays0) {
        code = "E_OVERLAY_SHAPE";
        site = siteKey;
        path = [
          "transport"
          "overlays"
        ];
        message = "transport.overlays must be a list";
        hints = [
          "Use transport.overlays = [ { peerSite = \"enterprise.site\"; terminateOn = \"core-node\"; mustTraverse = [\"policy\"]; } ... ]"
        ];
      };

      _needsCore =
        if overlays0 == [ ] then
          true
        else
          ensure (builtins.length coreNodes > 0) {
            code = "E_OVERLAY_NO_CORE";
            site = siteKey;
            path = [
              "transport"
              "overlays"
            ];
            message = "overlays require at least one core node";
            hints = [ "Add a topology.nodes.<name>.role = \"core\" node." ];
          };

      getPeer =
        ov:
        if ov ? peerSite then
          ov.peerSite
        else if ov ? peer then
          ov.peer
        else if ov ? toSite then
          ov.toSite
        else
          null;

      resolveTerminateOn =
        idx: ov:
        if ov ? terminateOn then
          ov.terminateOn
        else if builtins.length coreNodes == 1 then
          builtins.elemAt coreNodes 0
        else
          throwError {
            code = "E_OVERLAY_AMBIGUOUS_CORE";
            site = siteKey;
            path = [
              "transport"
              "overlays"
              idx
            ];
            message = "overlay.terminateOn is required when multiple core nodes exist";
            hints = [ "Set transport.overlays[].terminateOn to the core node name." ];
          };

      normalizeMustTraverse =
        idx: ov:
        let
          _present = ensure (ov ? mustTraverse) {
            code = "E_OVERLAY_MISSING_MUST_TRAVERSE";
            site = siteKey;
            path = [
              "transport"
              "overlays"
              idx
              "mustTraverse"
            ];
            message = "overlay.mustTraverse is required; compiler must not assume policy traversal";
            hints = [ "Set transport.overlays[].mustTraverse = [ \"policy\" ]." ];
          };

          mt0 = ov.mustTraverse;

          _shape2 = ensure (builtins.isList mt0) {
            code = "E_OVERLAY_MUST_TRAVERSE_SHAPE";
            site = siteKey;
            path = [
              "transport"
              "overlays"
              idx
              "mustTraverse"
            ];
            message = "overlay.mustTraverse must be a list of strings";
            hints = [ "Use mustTraverse = [ \"policy\" ] (or additional unit roles as needed)." ];
          };

          _items = ensure (builtins.all builtins.isString mt0) {
            code = "E_OVERLAY_MUST_TRAVERSE_SHAPE";
            site = siteKey;
            path = [
              "transport"
              "overlays"
              idx
              "mustTraverse"
            ];
            message = "overlay.mustTraverse must be a list of strings";
            hints = [ "Use mustTraverse = [ \"policy\" ]." ];
          };

          _requiresPolicy = ensure (builtins.elem "policy" mt0) {
            code = "E_OVERLAY_MUST_TRAVERSE_POLICY_REQUIRED";
            site = siteKey;
            path = [
              "transport"
              "overlays"
              idx
              "mustTraverse"
            ];
            message = "overlay traversal must explicitly include \"policy\"";
            hints = [ "Add \"policy\" to mustTraverse." ];
          };

          _force = builtins.deepSeq {
            inherit
              _present
              _shape2
              _items
              _requiresPolicy
              ;
          } true;
        in
        if _force then mt0 else mt0;

      normalizeOne =
        idx: ov:
        let
          _ovShape = ensure (builtins.isAttrs ov) {
            code = "E_OVERLAY_ENTRY_SHAPE";
            site = siteKey;
            path = [
              "transport"
              "overlays"
              idx
            ];
            message = "overlay entry must be an attrset";
            hints = [
              "Use { name = \"...\"; peerSite = \"enterprise.site\"; terminateOn = \"s-router-core\"; mustTraverse = [\"policy\"]; }."
            ];
          };

          peer = getPeer ov;

          _peer = ensure (peer != null && builtins.isString peer && peer != "") {
            code = "E_OVERLAY_MISSING_PEER";
            site = siteKey;
            path = [
              "transport"
              "overlays"
              idx
            ];
            message = "overlay must set peerSite (string)";
            hints = [ "Set transport.overlays[].peerSite = \"enterprise.site\"." ];
          };

          term = resolveTerminateOn idx ov;

          _termExists = ensure (builtins.elem term nodeNames) {
            code = "E_OVERLAY_UNKNOWN_TERMINATION";
            site = siteKey;
            path = [
              "transport"
              "overlays"
              idx
              "terminateOn"
            ];
            message = "overlay termination node '${term}' does not exist";
            hints = [ "Set terminateOn to an existing topology.nodes.<name>." ];
          };

          _termIsCore = ensure (builtins.elem term coreNodes) {
            code = "E_OVERLAY_TERMINATE_NON_CORE";
            site = siteKey;
            path = [
              "transport"
              "overlays"
              idx
              "terminateOn"
            ];
            message = "overlay must terminate on a core node (got '${term}')";
            hints = [ "Set terminateOn to a node with role = \"core\"." ];
          };

          mustTraverse = normalizeMustTraverse idx ov;

          _force = builtins.deepSeq {
            inherit
              _ovShape
              _peer
              _termExists
              _termIsCore
              mustTraverse
              ;
          } true;

          name = ov.name or "overlay-${toString idx}";
        in
        if _force then
          {
            inherit name;
            peerSite = peer;
            terminateOn = term;
            mustTraverse = mustTraverse;
          }
        else
          null;

      overlaysN = lib.imap0 normalizeOne overlays0;

      _uniqNames = assertUnique "overlay name" (map (o: o.name) overlaysN);

      _forced = builtins.deepSeq {
        inherit
          _shape
          _needsCore
          _uniqNames
          ;
      } true;
    in
    if _forced then overlaysN else overlaysN;

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

      coreUpstreams = lib.listToAttrs (
        map (n: {
          name = n;
          value =
            let
              us = normalizeUpstreams (nodes.${n}.upstreams or null);

              _required = ensure (builtins.length us > 0) {
                code = "E_CORE_UPSTREAMS_REQUIRED";
                site = siteKey;
                path = [
                  "topology"
                  "nodes"
                  n
                  "upstreams"
                ];
                message = "core node '${n}' must define at least one upstream";
                hints = [
                  "Set topology.nodes.${n}.upstreams = { default = {}; }."
                ];
              };
            in
            if _required then us else us;
        }) coreNodes
      );

      allUpstreamCounts = map (n: builtins.length (coreUpstreams.${n} or [ ])) coreNodes;

      anyMultiWan = builtins.any (c: c > 1) allUpstreamCounts;

      natModel = {
        enabled = builtins.length ingressExpanded > 0;
        ingress = ingressExpanded;
      };

      communicationContract = {
        allowedRelations = normalizedRules;
        nat = natModel;
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

      overlays = normalizeTransportOverlays siteKey topo declared;

      overlayNames = map (o: o.name) overlays;

      overlayHasExplicitAllow =
        ovName:
        builtins.any (
          r: (r.action or "deny") == "allow" && (r.to ? external) && r.to.external == ovName
        ) normalizedRules;

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
              message = "overlay '${ov.name}' requires an explicit allow rule to external='${ov.name}' (no implicit policy traversal)";
              hints = [
                "Add policy.rules = [ { from = { kind = \"tenant\"; name = \"...\"; }; to = { external = \"${ov.name}\"; }; action = \"allow\"; proto = [\"any\"]; priority = ...; } ... ]."
                "Or remove the overlay if inter-site communication is not intended."
              ];
            }
          ) overlays;

      model = {
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

        transport = {
          overlays = overlays;
        };

        addressPools = semantic.addressPools or { };

        routerLoopbacks = loopbacks;

        units = unitIsolation;

        upstreams = {
          multiWan = anyMultiWan;
          cores = coreUpstreams;
        };

        inherit communicationContract;
      };

      _forced = builtins.deepSeq {
        inherit
          _addrSafe
          _topoValid
          _uniqServices
          _uniqTenants
          _uniqRuleIds
          ;
        normalizedRules = normalizedRules;
        ingressExpanded = ingressExpanded;
        coreUpstreams = coreUpstreams;
        overlays = overlays;
        overlayNames = overlayNames;
        _overlayPolicyRequired = _overlayPolicyRequired;
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
          schemaVersion = 4;
          provenance = {
            originalInputs = inputs;
          };
        };
      };
    in
    canonicalize out;
}
