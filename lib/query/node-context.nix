{ lib }:

{
  all ? null,
  routed,
  nodeName ? null,
  linkName ? null,
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

  membersOf = l: lib.unique ((l.members or [ ]) ++ (builtins.attrNames (l.endpoints or { })));

  getEp = l: n: (l.endpoints or { }).${n} or { };

  mkIface = l: ep: {
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

  corePrefix = "${fabricHost}-";
  isCoreContext = lib.hasPrefix corePrefix requestedNode;

  parts = lib.splitString "-" requestedNode;
  lastPart = if parts == [ ] then "" else lib.last parts;

  haveVidSuffix = isCoreContext && (builtins.match "^[0-9]+$" lastPart != null);

  vid = if haveVidSuffix then lib.toInt lastPart else null;

  _assertContextSuffix =
    if isCoreContext && (lib.length parts) >= 4 && !haveVidSuffix then
      throw "node-context: invalid core context node '${requestedNode}': expected numeric vlan suffix, e.g. '${fabricHost}-<ctx>-<vid>'"
    else
      true;

  tenant4Dst = if vid == null then null else "${routed.tenantV4Base}.${toString vid}.0/24";
  tenant6Dst = if vid == null then null else "${routed.ulaPrefix}:${toString vid}::/64";

  keepTenantRoute4 = r: if vid == null then true else (r ? dst) && r.dst == tenant4Dst;

  keepTenantRoute6 = r: if vid == null then true else (r ? dst) && r.dst == tenant6Dst;

  scopeTenantRoutes =
    iface:
    if vid == null then
      iface
    else if (iface.kind or null) == "p2p" then
      iface
      // {
        routes4 = builtins.filter keepTenantRoute4 (iface.routes4 or [ ]);
        routes6 = builtins.filter keepTenantRoute6 (iface.routes6 or [ ]);
      }
    else
      iface;

  isDefault4 = r: (r ? dst) && r.dst == "0.0.0.0/0";
  isDefault6 = r: (r ? dst) && r.dst == "::/0";

  isWanIface =
    iface:
    (iface ? kind && iface.kind == "wan")
    || (iface ? carrier && iface.carrier == "wan")
    || (iface ? gateway && iface.gateway == true);

  keepRoute4 = iface: r: (r ? via4) || ((isDefault4 r) && (isWanIface iface));
  keepRoute6 = iface: r: (r ? via6) || ((isDefault6 r) && (isWanIface iface));

  sanitizeIface =
    iface:
    iface
    // {
      routes4 = builtins.filter (keepRoute4 iface) (iface.routes4 or [ ]);
      routes6 = builtins.filter (keepRoute6 iface) (iface.routes6 or [ ]);
    };

  rewriteVlanId =
    iface:
    if vid != null && iface.kind == "p2p" && iface.vlanId != null then
      iface // { vlanId = iface.vlanId + vid; }
    else
      iface;

  directLinks = lib.filterAttrs (_: l: lib.elem requestedNode (membersOf l)) links;

  inheritedP2pLinks =
    if isCoreContext then
      lib.filterAttrs (_: l: (l.kind or null) == "p2p" && lib.elem fabricHost (membersOf l)) links
    else
      { };

  directIfaces = lib.mapAttrs (
    _: l: sanitizeIface (scopeTenantRoutes (rewriteVlanId (mkIface l (getEp l requestedNode))))
  ) directLinks;

  inheritedIfaces = lib.mapAttrs (
    _: l: sanitizeIface (scopeTenantRoutes (rewriteVlanId (mkIface l (getEp l fabricHost))))
  ) inheritedP2pLinks;

  enrichedInterfaces = inheritedIfaces // directIfaces;

  selected =
    if linkName == null then
      enrichedInterfaces
    else if enrichedInterfaces ? "${linkName}" then
      enrichedInterfaces.${linkName}
    else
      throw "node-context: link '${linkName}' not found on node '${requestedNode}'";

in
builtins.seq _assertContextSuffix (sanitize {
  node = requestedNode;
  link = linkName;
  config = selected;
})
