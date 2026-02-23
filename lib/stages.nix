{ lib }:

let
  flattenSites = import ./flatten-sites.nix { inherit lib; };
  normalizeSite = import ./normalize/from-user-input.nix { inherit lib; };
  allocator = import ./allocators/pinned-allocator.nix { inherit lib; };

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

  capabilityProto =
    policy: capName:
    let
      catalog = if policy ? catalog then policy.catalog else { };
      caps = if catalog ? capabilities then catalog.capabilities else { };
      cap = if builtins.isAttrs caps && builtins.hasAttr capName caps then caps.${capName} else null;
    in
    if cap == null then
      throw "stages: referenced capability '${capName}' not declared in policy.catalog.capabilities"
    else
      matchListToProto (if cap ? match then cap.match else [ ]);

  egressProfileProto =
    policy: profileName:
    let
      profiles = if policy ? egressProfiles then policy.egressProfiles else { };
      prof =
        if builtins.isAttrs profiles && builtins.hasAttr profileName profiles then
          profiles.${profileName}
        else
          null;
    in
    if prof == null then
      throw "stages: referenced egressProfile '${profileName}' not declared in policy.egressProfiles"
    else
      matchListToProto (if prof ? match then prof.match else [ ]);

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
    policy: idx: rule:
    let
      from0 = if rule ? from then rule.from else { };
      to0 = if rule ? to then rule.to else { };

      from =
        if (from0 ? kind) && (from0.kind == "tenant") && (from0 ? name) then
          { subject = from0.name; }
        else
          throw "stages: rule.from must be { kind=\"tenant\"; name=...; }";

      to =
        if to0 ? external then
          { external = to0.external; }
        else if (to0 ? kind) && (to0.kind == "tenant") && (to0 ? name) then
          ({ subject = to0.name; } // (if to0 ? capability then { capability = to0.capability; } else { }))
        else
          throw "stages: rule.to must be either { external = ...; } or { kind=\"tenant\"; name=...; ... }";

      proto =
        if rule ? proto then
          rule.proto
        else if rule ? egressProfile then
          egressProfileProto policy rule.egressProfile
        else if to0 ? capability then
          capabilityProto policy to0.capability
        else
          [ "any" ];
    in
    {
      source = mkRuleSource idx rule;
      from = from;
      to = to;
      action = if rule ? action then rule.action else "deny";
      proto = proto;
    };

  mkNatIngressRelation =
    idx: i:
    let
      m = if i ? match then i.match else { };
      l4 = if m ? l4 then m.l4 else "tcp";
      dports = if m ? dports then m.dports else [ ];
      proto =
        if l4 == "any" then
          [ "any" ]
        else if dports == [ ] then
          [ l4 ]
        else
          map (p: "${l4}/${toString p}") dports;

      svc =
        if
          (i ? toService)
          && builtins.isAttrs i.toService
          && (i.toService ? kind)
          && (i.toService.kind == "service")
          && (i.toService ? name)
        then
          i.toService.name
        else
          throw "stages: policy.nat.ingress[].toService must be { kind=\"service\"; name=...; }";

      ext = if i ? fromExternal then i.fromExternal else "default";
    in
    {
      source = {
        kind = "nat.ingress";
        index = idx;
        toService = svc;
        fromExternal = ext;
      };
      from = {
        external = ext;
      };
      to = {
        service = svc;
      };
      action = "allow";
      proto = proto;
    };

  buildModel =
    siteKey: declared: semantic:
    let
      policy = if declared ? policy then declared.policy else { };

      rules0 = if policy ? rules then policy.rules else [ ];
      normalizedRules = lib.imap0 (idx: r: normalizeRuleWithProvenance policy idx r) rules0;

      nat0 = if policy ? nat then policy.nat else { };
      ingress0 = if nat0 ? ingress then nat0.ingress else [ ];
      natIngressRelations = lib.imap0 mkNatIngressRelation ingress0;

      allowedRelations = normalizedRules ++ natIngressRelations;

      trafficClasses = lib.unique (
        lib.concatMap (rel: if rel ? proto then rel.proto else [ "any" ]) allowedRelations
      );

      enforcement = {
        requirePolicyEngine = true;
      }
      // (if policy ? authority then { authorityRoles = policy.authority; } else { })
      // (if policy ? transit then { transitForwarder = policy.transit; } else { });

      model0 = if policy ? model then policy.model else { };
      precedence0 = if model0 ? precedence then model0.precedence else { };

      precedence1 = precedence0 // {
        mode = if precedence0 ? mode then precedence0.mode else "priority";

        defaultPriority = if precedence0 ? defaultPriority then precedence0.defaultPriority else 1000;

        higherWins = if precedence0 ? higherWins then precedence0.higherWins else true;
      };

      subjectBinding0 = if model0 ? subjectBinding then model0.subjectBinding else { };

      subjectBinding1 = subjectBinding0 // {
        mode = if subjectBinding0 ? mode then subjectBinding0.mode else "ownedPrefixes";

        endpointSets = if subjectBinding0 ? endpointSets then subjectBinding0.endpointSets else [ ];
      };

      model1 = model0 // {
        precedence = precedence1;
        subjectBinding = subjectBinding1;
      };

      communicationContract = {
        trafficClasses = trafficClasses;
        allowedRelations = allowedRelations;

        semantics = {
          model = model1;
          externalCatalog = if policy ? externalCatalog then policy.externalCatalog else { };
          catalog = if policy ? catalog then policy.catalog else { };
          capabilityBindings = if policy ? capabilityBindings then policy.capabilityBindings else [ ];
          nat = nat0;
          invariants = if policy ? invariants then policy.invariants else [ ];
          enforcement = if policy ? enforcement then policy.enforcement else { };

          natIngressImpliesAllow = true;

          rawRules = rules0;
        };
      }
      // (if enforcement != { } then { inherit enforcement; } else { });

      topo = if declared ? topology then declared.topology else { };
      nodes = if topo ? nodes then topo.nodes else { };
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
      enterprise = if semantic ? enterprise then semantic.enterprise else "default";

      domains = {
        tenants = tenants;
      };

      attachment = if semantic ? attachments then semantic.attachments else [ ];

      transit = {
        ordering = if semantic ? transit && semantic.transit ? links then semantic.transit.links else [ ];
        addressAuthority =
          if semantic ? transit && semantic.transit ? pool then semantic.transit.pool else null;
      };

      addressPools = if semantic ? addressPools then semantic.addressPools else { };

      routerLoopbacks = loopbacks;

      inherit communicationContract;
    };

  compileSite =
    siteKey: declared:
    let
      semantic = normalizeSite declared;
      model = buildModel siteKey declared semantic;
    in
    model;

in
{
  run =
    inputs:
    let
      sites = flattenSites inputs;
      compiled = lib.mapAttrs compileSite sites;
    in
    {
      sites = compiled;
    };
}
