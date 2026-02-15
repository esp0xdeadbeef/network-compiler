{
  lib,
  ulaPrefix,
  tenantV4Base,
}:

topoRaw:

let
  links = topoRaw.links or { };
  nodes0 = topoRaw.nodes or { };

  # The "fabric host" name (bridge host). We keep it on the model so we can
  # create virtual routing-context nodes that inherit its ifs.
  coreFabricNodeName = topoRaw.coreNodeName or null;

  getEp = l: n: (l.endpoints or { }).${n} or { };

  # BUGFIX:
  # Treat endpoint keys as implicit members, so nodes like "${coreNodeName}-isp-1"
  # participate even if links.members only contains coreFabricNodeName.
  membersOf =
    l:
    lib.unique ((l.members or [ ]) ++ (builtins.attrNames (l.endpoints or { })));

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
    nodeName:
    lib.filter (lname: lib.elem nodeName (membersOf links.${lname})) (lib.attrNames links);

  interfacesForNode =
    nodeName:
    lib.listToAttrs (
      map (lname: {
        name = lname;
        value = mkIface lname links.${lname} nodeName;
      }) (linkNamesForNode nodeName)
    );

  # Collect all endpoint-declared nodes that may not exist in topoRaw.nodes.
  endpointNodes =
    lib.unique (
      lib.concatMap (l: builtins.attrNames (l.endpoints or { })) (lib.attrValues links)
    );

  # Create missing nodes. If the node name starts with "${coreNodeName}-",
  # inherit ifs from the fabric host "${coreNodeName}" (same physical box).
  mkMissingNode =
    n:
    if nodes0 ? "${n}" then
      null
    else if coreFabricNodeName != null
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
      # Generic fallback: create node with only lan carrier.
      {
        name = n;
        value = {
          ifs = { lan = "lan"; };
        };
      };

  missingNodes = lib.filter (x: x != null) (map mkMissingNode endpointNodes);

  nodes1 = nodes0 // (lib.listToAttrs missingNodes);

  nodes' = lib.mapAttrs (
    n: node:
    node // {
      interfaces = interfacesForNode n;
    }
  ) nodes1;

in
topoRaw
// {
  inherit ulaPrefix tenantV4Base;
  nodes = nodes';
}

