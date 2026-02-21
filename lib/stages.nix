{ lib }:

let
  normalizeSite = import ./normalize/from-user-input.nix { inherit lib; };
  compileSite = import ./compile-site.nix { inherit lib; };
  invariants = import ./fabric/invariants/default.nix { inherit lib; };

  alloc = import ./p2p/alloc.nix { inherit lib; };

  assert_ = cond: msg: if cond then true else throw msg;

  isSite = v: builtins.isAttrs v && (v ? nodes || v ? links || v ? p2p-pool);

  isCompiledSite = v: builtins.isAttrs v && v ? nodes && v ? links && builtins.isAttrs v.links;

  flattenSites =
    top:
    let
      topNames = builtins.attrNames top;
      addOne =
        acc: name:
        let
          v = top.${name};
        in
        if isSite v then
          acc // { "${name}" = v; }
        else if builtins.isAttrs v then
          let
            siteNames = builtins.attrNames v;
            _nonEmpty = assert_ (
              siteNames != [ ]
            ) "stages.flatten: enterprise '${name}' must contain at least one site";
            addSite =
              acc2: sname:
              let
                sv = v.${sname};
              in
              if isSite sv then
                acc2
                // {
                  "${name}.${sname}" = sv // {
                    enterprise = name;
                    siteName = sname;
                  };
                }
              else
                throw "stages.flatten: enterprise '${name}' contains non-site attribute '${sname}'";
          in
          builtins.foldl' addSite acc siteNames
        else
          throw "stages.flatten: top-level attribute '${name}' must be a site or enterprise attrset";
    in
    builtins.foldl' addOne { } topNames;

  normalizeAll = sites: lib.mapAttrs (_: s: normalizeSite s) sites;

  checkSiteAll =
    sites: builtins.deepSeq (lib.mapAttrs (_: s: invariants.checkSite { site = s; }) sites) true;

  checkAllGlobal = sites: builtins.deepSeq (invariants.checkAll { inherit sites; }) true;

  runPreInvariants =
    sites: builtins.seq (checkSiteAll sites) (builtins.seq (checkAllGlobal sites) sites);

  compileAll = sites: lib.mapAttrs (_: s: if isCompiledSite s then s else compileSite s) sites;

  runPostInvariants = compiled: builtins.seq (checkSiteAll compiled) compiled;

  isNetworkAttr =
    name: v:
    builtins.isAttrs v
    && (v ? ipv4 || v ? ipv6)
    && !(lib.elem name [
      "role"
      "interfaces"
      "networks"
    ]);

  networksOf =
    node:
    if node ? networks && builtins.isAttrs node.networks then
      node.networks
    else
      lib.filterAttrs isNetworkAttr node;

  segmentsFromProcessCell =
    site:
    let
      pc = site.processCell or { };
      owned = pc.owned or { };
      tenants = owned.tenants or [ ];
      services = owned.services or [ ];
    in
    {
      inherit tenants services;
    };

  tenantsFromAccessNetworks =
    site:
    let
      nodes = site.nodes or { };

      accessNodes = lib.filterAttrs (_: n: (n.role or null) == "access") nodes;

      nets = lib.concatMap (
        nodeName:
        let
          node = accessNodes.${nodeName};
          ns = networksOf node;
        in
        lib.mapAttrsToList (netName: net: {
          name = netName;
          ipv4 = net.ipv4 or null;
          ipv6 = net.ipv6 or null;
          kind = net.kind or null;
        }) ns
      ) (builtins.attrNames accessNodes);

      mkKey = t: "tenants:${t.name}";
      keyed = lib.listToAttrs (
        map (t: {
          name = mkKey t;
          value = t;
        }) nets
      );
    in
    {
      tenants = lib.mapAttrsToList (_: v: v) keyed;
    };

  chooseSegments =
    site:
    let
      pcSeg = segmentsFromProcessCell site;

      derived = tenantsFromAccessNetworks site;

      tenants = if (pcSeg.tenants or [ ]) != [ ] then pcSeg.tenants else derived.tenants or [ ];

      services = pcSeg.services or [ ];
    in
    {
      inherit tenants services;
    };

  attachmentsFromAccess =
    site:
    let
      nodes = site.nodes or { };

      accessNodes = lib.filterAttrs (_: n: (n.role or null) == "access") nodes;

      attachForNode =
        nodeName:
        let
          node = accessNodes.${nodeName};
          ns = networksOf node;
        in
        lib.mapAttrsToList (netName: _net: {
          unit = nodeName;
          segment = "tenants:${netName}";
        }) ns;
    in
    lib.concatMap attachForNode (builtins.attrNames accessNodes);

  mkSiteGraph =
    siteName: site:
    let
      seg = chooseSegments site;

      tenantsGraph = map (t: {
        name = t.name;
        ipv4 = t.ipv4 or null;
        ipv6 = t.ipv6 or null;
      }) (seg.tenants or [ ]);

      servicesGraph = map (s: {
        name = s.name;
        prefixes = s.prefixes or [ ];
      }) (seg.services or [ ]);
    in
    {
      transit = {
        links = site.links or [ ];
        pool = site.p2p-pool or null;
      };

      segments = {
        tenants = tenantsGraph;
        services = servicesGraph;
      };

      attachments = attachmentsFromAccess site;
    };

  mkP2P =
    _siteName: site:
    let
      pool = site.p2p-pool or null;
      p2pLinks = if pool == null then { } else alloc.alloc { site = site; };
    in
    {
      inherit pool;
      links = p2pLinks;
    };

in
{
  flatten = inputs: flattenSites inputs;

  normalize = inputs: normalizeAll (flattenSites inputs);

  "invariants-pre" = inputs: runPreInvariants (normalizeAll (flattenSites inputs));

  compile = inputs: compileAll (runPreInvariants (normalizeAll (flattenSites inputs)));

  "invariants-post" =
    inputs: runPostInvariants (compileAll (runPreInvariants (normalizeAll (flattenSites inputs))));

  checkSites = sites: builtins.seq (checkSiteAll sites) (builtins.seq (checkAllGlobal sites) true);

  p2p = inputs: lib.mapAttrs mkP2P (runPreInvariants (normalizeAll (flattenSites inputs)));

  siteGraph =
    inputs: lib.mapAttrs mkSiteGraph (runPreInvariants (normalizeAll (flattenSites inputs)));
}
