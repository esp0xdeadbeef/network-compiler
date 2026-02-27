{ lib }:

let
  flattenSites = import ./flatten-sites.nix { inherit lib; };
  normalizeSite = import ./normalize/from-user-input.nix { inherit lib; };
  allocator = import ./allocators/pinned-allocator.nix { inherit lib; };

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
      keys = builtins.attrNames compiledFlat;

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

  matchListToProto =
    matches:
    let
      ms = if matches == null then [ ] else matches;

      one =
        m:
        let
          l4 = if builtins.isAttrs m && m ? l4 then m.l4 else "any";
          dports = if builtins.isAttrs m && m ? dports then m.dports else [ ];
        in
        if l4 == "any" then
          [ "any" ]
        else if dports == [ ] then
          [ l4 ]
        else
          map (p: "${l4}/${toString p}") dports;
    in
    lib.unique (lib.concatMap one ms);

  buildCapabilityIndex =
    policy:
    let
      catalog = policy.catalog or { };
      services = catalog.services or [ ];

      addService =
        acc: svc:
        let
          provides = svc.provides or [ ];
          proto = if svc ? match then matchListToProto svc.match else [ ];
          addCap =
            acc2: capName: if builtins.hasAttr capName acc2 then acc2 else acc2 // { "${capName}" = proto; };
        in
        builtins.foldl' addCap acc provides;
    in
    builtins.foldl' addService { } services;

  capabilityProto =
    capIndex: capName:
    if builtins.hasAttr capName capIndex then
      capIndex.${capName}
    else
      throw "stages: referenced capability '${capName}' not provided by any service";

  mkRuleSource =
    idx: rule:
    let
      rid = if rule ? id then rule.id else "rule-${toString idx}";
      prio = if rule ? priority then rule.priority else null;
    in
    {
      kind = "rule";
      index = idx;
      id = rid;
    }
    // (if prio == null then { } else { priority = prio; });

  normalizeRuleWithProvenance =
    capIndex: idx: rule:
    let
      from0 = rule.from or { };
      to0 = rule.to or { };

      from =
        if (from0 ? kind) && from0.kind == "tenant" && (from0 ? name) then
          { subject = from0.name; }
        else
          throw "stages: rule.from must be { kind=\"tenant\"; name=...; }";

      to =
        if to0 ? external then
          { external = to0.external; }
        else if (to0 ? kind) && to0.kind == "tenant" && (to0 ? name) then
          ({ subject = to0.name; } // (if to0 ? capability then { capability = to0.capability; } else { }))
        else
          throw "stages: rule.to must be either { external = ...; } or { kind=\"tenant\"; name=...; ... }";

      proto =
        if rule ? proto then
          rule.proto
        else if to0 ? capability then
          capabilityProto capIndex to0.capability
        else
          [ "any" ];
    in
    {
      source = mkRuleSource idx rule;
      from = from;
      to = to;
      action = rule.action or "deny";
      proto = proto;
    };

  normalizeNatIngress =
    policy:
    let
      catalog = policy.catalog or { };
      services = catalog.services or [ ];

      serviceIndex = builtins.listToAttrs (
        map (s: {
          name = s.name;
          value = s;
        }) services
      );

      nat0 = policy.nat or { };
      ingress0 = nat0.ingress or [ ];

      expandOne =
        n:
        let
          svcRef = n.toService or null;
          _ =
            if svcRef == null || !(svcRef ? name) then
              throw "stages: nat.ingress entry must reference toService.name"
            else
              true;

          svcName = svcRef.name;

          _svc =
            if builtins.hasAttr svcName serviceIndex then
              serviceIndex.${svcName}
            else
              throw "stages: nat.ingress references unknown service '${svcName}'";
        in
        {
          fromExternal = n.fromExternal or "default";
          toService = {
            kind = "service";
            name = svcName;
          };
        };
    in
    map expandOne ingress0;

  validateCoreNat =
    nodes:
    let
      names = builtins.attrNames nodes;

      checkOne =
        name:
        let
          node = nodes.${name};
          role = node.role or null;
          nat = node.nat or null;
          mode = if nat != null && nat ? mode then nat.mode else null;

          isCore = role == "core";
        in
        if !isCore then
          true
        else if nat == null then
          throw ''
            stages: node '${name}' (role="core") must define nat

            Example:

              nat = {
                mode = "none";
              };

            or

              nat = {
                mode = "custom";
                egress = {
                  strategy = "masquerade";
                  source = "interface";
                };
                ingress = {
                  allowPortForward = true;
                  hairpin = false;
                };
              };
          ''
        else if mode == "none" then
          true
        else if mode == "custom" then
          true
        else
          throw ''
            stages: node '${name}' (role="core") has invalid nat.mode '${toString mode}'

            Allowed values:
              - "none"
              - "custom"
          '';
    in
    map checkOne names;

  buildModel =
    siteKey: declared: semantic:
    let
      policy = declared.policy or { };

      capIndex = buildCapabilityIndex policy;

      rules0 = policy.rules or [ ];
      normalizedRules = lib.imap0 (idx: r: normalizeRuleWithProvenance capIndex idx r) rules0;

      ingressExpanded = normalizeNatIngress policy;

      communicationContract = {
        allowedRelations = normalizedRules;

        nat = {
          ingress = ingressExpanded;
        };
      };

      topo = declared.topology or { };
      nodes = topo.nodes or { };

      _ = validateCoreNat nodes;

      nodeNames = lib.sort builtins.lessThan (builtins.attrNames nodes);

      localPool =
        if semantic ? addressPools && semantic.addressPools ? local then
          semantic.addressPools.local
        else
          null;

      allocV4 = allocator.mkIPv4Allocator localPool;
      allocV6 = allocator.mkIPv6Allocator localPool;

      loopbacks = lib.listToAttrs (
        lib.imap0 (idx: name: {
          name = name;
          value = {
            ipv4 = allocV4 idx;
            ipv6 = allocV6 idx;
          };
        }) nodeNames
      );

      tenants =
        if semantic ? segments && semantic.segments ? tenants then semantic.segments.tenants else [ ];

    in
    {
      id = siteKey;
      enterprise = semantic.enterprise or "default";

      domains = {
        tenants = tenants;
      };

      attachment = semantic.attachments or [ ];

      transit = {
        ordering = if semantic ? transit && semantic.transit ? links then semantic.transit.links else [ ];
      };

      addressPools = semantic.addressPools or { };

      routerLoopbacks = loopbacks;

      inherit communicationContract;
    };

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
    in
    {
      sites = compiledGrouped;
    };
}
