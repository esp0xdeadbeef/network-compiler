{
  lib,
  ulaPrefix,
  tenantV4Base,

  policyNodeName,
  coreNodeName,

  coreRoutingNodeName ? null,
}:

topoResolved:

let
  topo0 = topoResolved // {
    defaultRouteMode =
      if topoResolved ? defaultRouteMode then topoResolved.defaultRouteMode else "default";
  };

  nodes = topo0.nodes or { };
  links0 = topo0.links or { };

  addr = import ../model/addressing.nix { inherit lib; };

  expandPolicyCore =
    topo:
    let
      links = topo.links or { };

      base = links."policy-core" or null;

      isWan = l: (l.kind or null) == "wan";

      wanLinks = lib.filter isWan (lib.attrValues links);

      ctxFromEndpointKey =
        k: if lib.hasPrefix "${coreNodeName}-" k then lib.removePrefix "${coreNodeName}-" k else null;

      ctxsRaw = lib.concatMap (
        l: map ctxFromEndpointKey (builtins.attrNames (l.endpoints or { }))
      ) wanLinks;
      ctxs = lib.sort (a: b: a < b) (lib.unique (lib.filter (x: x != null && x != "") ctxsRaw));

      baseVlan = if base != null && (base ? vlanId) then base.vlanId else null;

      mkOne =
        i: ctx:
        let
          vlanId = baseVlan + i;
          coreCtx = "${coreNodeName}-${ctx}";
          members = [
            policyNodeName
            coreCtx
          ];
          lname = "policy-core-${ctx}";
        in
        {
          name = lname;
          value = {
            kind = "p2p";
            scope = "internal";
            carrier = "lan";
            inherit vlanId members;
            name = lname;

            endpoints = {
              "${policyNodeName}" = {
                addr4 = addr.mkP2P4 {
                  v4Base = tenantV4Base;
                  inherit vlanId members;
                  node = policyNodeName;
                };
                addr6 = addr.mkP2P6 {
                  inherit ulaPrefix vlanId members;
                  node = policyNodeName;
                };
              };

              "${coreCtx}" = {
                addr4 = addr.mkP2P4 {
                  v4Base = tenantV4Base;
                  inherit vlanId members;
                  node = coreCtx;
                };
                addr6 = addr.mkP2P6 {
                  inherit ulaPrefix vlanId members;
                  node = coreCtx;
                };
              };
            };
          };
        };

      expanded =
        if base == null || baseVlan == null || ctxs == [ ] then
          null
        else
          lib.listToAttrs (lib.imap0 mkOne ctxs);

      links' =
        if expanded == null then links else (builtins.removeAttrs links [ "policy-core" ]) // expanded;
    in
    topo // { links = links'; };

  topo1 = expandPolicyCore topo0;

  candidates = lib.filter (n: lib.hasPrefix "${coreNodeName}-" n) (builtins.attrNames nodes);
  sortedCandidates = lib.sort (a: b: a < b) candidates;

  derivedCoreRouting =
    if coreRoutingNodeName != null then
      if !(nodes ? "${coreRoutingNodeName}") then
        throw ''
          routing-gen: coreRoutingNodeName "${coreRoutingNodeName}" does not exist in topology nodes.
        ''
      else
        coreRoutingNodeName
    else if nodes ? "${coreNodeName}" then
      coreNodeName
    else if sortedCandidates != [ ] then
      lib.head sortedCandidates
    else
      throw ''
        routing-gen: cannot pick a core routing node.

        coreNodeName (fabric host) = "${coreNodeName}"

        Expected one of:
          - set coreRoutingNodeName explicitly
          - ensure node "${coreNodeName}" exists
          - or define at least one node matching "${coreNodeName}-*"
      '';

  pre = import ./assertions/pre.nix {
    inherit lib policyNodeName;
    coreNodeName = derivedCoreRouting;
  } topo1;

  _pre = lib.assertMsg (lib.all (a: a.assertion) pre.assertions) (
    lib.concatStringsSep "\n" (map (a: a.message) (lib.filter (a: !a.assertion) pre.assertions))
  );

  step0 = import ./routing/upstreams.nix { inherit lib; } topo1;

  step0b = import ./routing/wan-runtime.nix {
    inherit lib ulaPrefix tenantV4Base;
  } step0;

  step1 = import ./routing/tenant-lan.nix {
    inherit lib ulaPrefix;
  } step0b;

  internet = import ./routing/public-prefixes.nix { inherit lib; } step1;

  capabilities = import ./routing/capabilities.nix { inherit lib; } step1;

  tenantVids = lib.unique (
    lib.filter (x: x != null) (
      lib.concatMap (
        l:
        lib.concatMap (
          ep:
          let
            t = ep.tenant or null;
          in
          if builtins.isAttrs t && t ? vlanId then [ t.vlanId ] else [ ]
        ) (lib.attrValues (l.endpoints or { }))
      ) (lib.attrValues (step1.links or { }))
    )
  );

  authority = {
    authorityNode = policyNodeName;
    byTenantVlan = lib.genAttrs (map toString tenantVids) (_: policyNodeName);
  };

  topoWithRoutingMaps = step1 // {
    _internet = internet;
    _routingMaps = {
      inherit capabilities authority;
    };
    defaultRouteMode = topo1.defaultRouteMode;
  };

  step2 = import ./routing/policy-access.nix {
    inherit
      lib
      ulaPrefix
      tenantV4Base
      policyNodeName
      ;
  } topoWithRoutingMaps;

  step3 = import ./routing/policy-core.nix {
    inherit
      lib
      ulaPrefix
      tenantV4Base
      policyNodeName
      coreNodeName
      ;
  } step2;

  post = import ./assertions/post.nix {
    inherit lib policyNodeName coreNodeName;
  } step3;

  _post = lib.assertMsg (lib.all (a: a.assertion) post.assertions) (
    lib.concatStringsSep "\n" (map (a: a.message) (lib.filter (a: !a.assertion) post.assertions))
  );

  materialized = import ../topology-resolve.nix {
    inherit lib ulaPrefix tenantV4Base;
  } step3;

  validatedRouting = import ./routing/validate-invariants.nix {
    inherit
      lib
      ulaPrefix
      tenantV4Base
      policyNodeName
      coreNodeName
      ;
  } materialized;

  out = validatedRouting // {
    coreRoutingNodeName = derivedCoreRouting;
  };

in
builtins.seq _pre (builtins.seq _post out)
