{ lib }:

{
  all ? null,
  routed,
  nodeName ? null,
  linkName ? null,

  # fabric host (bridge host) used for context-node detection
  fabricHost ? "s-router-core",
}:

let
  sanitize = import ./sanitize.nix { inherit lib; };

  requestedNode =
    if nodeName != null then
      nodeName
    else if routed ? coreRoutingNodeName && builtins.isString routed.coreRoutingNodeName then
      routed.coreRoutingNodeName
    else
      fabricHost;

  links = routed.links or { };

  # Treat endpoint keys as implicit members
  membersOf =
    l:
    lib.unique ((l.members or [ ]) ++ (builtins.attrNames (l.endpoints or { })));

  getEp = l: n: (l.endpoints or { }).${n} or { };

  mkIface =
    l: ep:
    {
      kind = l.kind or null;
      carrier = l.carrier or null;
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

  # Detect fabric context nodes like "s-router-core-isp-1"
  isFabricContext =
    lib.hasPrefix "${fabricHost}-" requestedNode;

  # Links directly owned by requested node (member or endpoint)
  directLinks =
    lib.filterAttrs (_: l: lib.elem requestedNode (membersOf l)) links;

  # Inherit fabric-host p2p links (e.g. policy-core) for context nodes,
  # but use the fabricHost endpoint config for those links.
  inheritedP2pLinks =
    if isFabricContext then
      lib.filterAttrs (_: l: (l.kind or null) == "p2p" && lib.elem fabricHost (membersOf l)) links
    else
      { };

  # Build interface map: direct = requestedNode endpoint, inherited p2p = fabricHost endpoint.
  directIfaces =
    lib.mapAttrs (_: l: mkIface l (getEp l requestedNode)) directLinks;

  inheritedIfaces =
    lib.mapAttrs (_: l: mkIface l (getEp l fabricHost)) inheritedP2pLinks;

  enrichedInterfaces = inheritedIfaces // directIfaces;

  selected =
    if linkName == null then
      enrichedInterfaces
    else if enrichedInterfaces ? "${linkName}" then
      enrichedInterfaces.${linkName}
    else
      throw "node-context: link '${linkName}' not found on node '${requestedNode}'";

in
sanitize {
  node = requestedNode;
  link = linkName;
  config = selected;
}

