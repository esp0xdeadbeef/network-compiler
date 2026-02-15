{
  lib,
  ulaPrefix,
  tenantV4Base,
}:

topoRaw:

let
  links = topoRaw.links or { };
  nodes0 = topoRaw.nodes or { };

  coreFabricNodeName = topoRaw.coreNodeName or null;

  getEp = l: n: (l.endpoints or { }).${n} or { };

  membersOf = l: lib.unique ((l.members or [ ]) ++ (builtins.attrNames (l.endpoints or { })));

  mkIface =
    linkName: l: nodeName:
    let
      ep = getEp l nodeName;
    in
    {
      kind = l.kind or null;
      carrier = l.carrier or "lan";
      vlanId = l.vlanId or null;

      tenant = ep.tenant or null;
      gateway = ep.gateway or false;
      export = ep.export or false;

      addr4 = ep.addr4 or null;
      addr6 = ep.addr6 or null;
      addr6Public = ep.addr6Public or null;

      routes4 = ep.routes4 or [ ];
      routes6 = ep.routes6 or [ ];
      ra6Prefixes = ep.ra6Prefixes or [ ];

      acceptRA = ep.acceptRA or false;
      dhcp = ep.dhcp or false;
    };

  linkNamesForNode =
    nodeName: lib.filter (lname: lib.elem nodeName (membersOf links.${lname})) (lib.attrNames links);

  interfacesForNode =
    nodeName:
    lib.listToAttrs (
      map (lname: {
        name = lname;
        value = mkIface lname links.${lname} nodeName;
      }) (linkNamesForNode nodeName)
    );

  endpointNodes = lib.unique (
    lib.concatMap (l: builtins.attrNames (l.endpoints or { })) (lib.attrValues links)
  );

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
      ) (lib.attrValues links)
    )
  );

  isNonNumericLast =
    n:
    let
      ps = lib.splitString "-" n;
      last = if ps == [ ] then "" else lib.last ps;
    in
    builtins.match "^[0-9]+$" last == null;

  coreCtxBases = lib.filter (
    n: coreFabricNodeName != null && lib.hasPrefix "${coreFabricNodeName}-" n && isNonNumericLast n
  ) endpointNodes;

  mkTenantCtxNodes =
    base:
    let
      ctx = lib.removePrefix "${coreFabricNodeName}-" base;
    in
    map (
      vid:
      let
        name = "${coreFabricNodeName}-${ctx}-${toString vid}";
      in
      if nodes0 ? "${name}" then
        null
      else
        {
          inherit name;
          value = {
            ifs = nodes0.${coreFabricNodeName}.ifs;
          };
        }
    ) tenantVids;

  mkMissingNode =
    n:
    if nodes0 ? "${n}" then
      null
    else if
      coreFabricNodeName != null
      && lib.hasPrefix "${coreFabricNodeName}-" n
      && nodes0 ? "${coreFabricNodeName}"
      && (nodes0.${coreFabricNodeName} ? ifs)
    then
      {
        name = n;
        value = {
          ifs = nodes0.${coreFabricNodeName}.ifs;
        };
      }
    else

      {
        name = n;
        value = {
          ifs = {
            lan = "lan";
          };
        };
      };

  missingFromEndpoints = lib.filter (x: x != null) (map mkMissingNode endpointNodes);

  tenantCtxNodes =
    if
      coreFabricNodeName != null
      && nodes0 ? "${coreFabricNodeName}"
      && (nodes0.${coreFabricNodeName} ? ifs)
      && tenantVids != [ ]
    then
      lib.filter (x: x != null) (lib.concatMap mkTenantCtxNodes coreCtxBases)
    else
      [ ];

  missingNodes = missingFromEndpoints ++ tenantCtxNodes;

  nodes1 = nodes0 // (lib.listToAttrs missingNodes);

  nodes' = lib.mapAttrs (
    n: node:
    node
    // {
      interfaces = interfacesForNode n;
    }
  ) nodes1;

in
topoRaw
// {
  inherit ulaPrefix tenantV4Base;
  nodes = nodes';
}
