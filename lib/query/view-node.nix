{ lib }:

nodeName: topo:

let
  sanitize = import ./sanitize.nix { inherit lib; };

  links0 = topo.links or { };

  getTenantVid =
    ep:
    if ep ? tenant && builtins.isAttrs ep.tenant && ep.tenant ? vlanId then ep.tenant.vlanId else null;

  membersOf = l: lib.unique ((l.members or [ ]) ++ (builtins.attrNames (l.endpoints or { })));

  fabricHost = topo.coreNodeName or "s-router-core";
  corePrefix = "${fabricHost}-";
  isCoreContext = lib.hasPrefix corePrefix nodeName;

  parts = lib.splitString "-" nodeName;
  lastPart = if parts == [ ] then "" else lib.last parts;

  haveVidSuffix = isCoreContext && (builtins.match "^[0-9]+$" lastPart != null);

  vid = if haveVidSuffix then lib.toInt lastPart else null;

  directLinks = lib.filterAttrs (_: l: lib.elem nodeName (membersOf l)) links0;

  inheritedP2pLinks =
    if vid != null then
      lib.filterAttrs (_: l: (l.kind or null) == "p2p" && lib.elem fabricHost (membersOf l)) links0
    else
      { };

  mkIfaceFrom = l: ep: {
    kind = l.kind or null;
    scope = l.scope or null;
    vlanId = l.vlanId or null;

    tenantVlanId = getTenantVid ep;

    addr4 = ep.addr4 or null;
    addr6 = ep.addr6 or null;

    routes4 = ep.routes4 or [ ];
    routes6 = ep.routes6 or [ ];
    ra6Prefixes = ep.ra6Prefixes or [ ];

    gateway = ep.gateway or false;
    acceptRA = ep.acceptRA or false;
    dhcp = ep.dhcp or false;
  };

  keepRoute4 =
    r:
    if vid == null then
      true
    else
      let
        tenantPrefix = "${topo.tenantV4Base}.${toString vid}.0/24";
      in
      (r.dst or "") == tenantPrefix;

  keepRoute6 =
    r:
    if vid == null then
      true
    else
      let
        tenantPrefix = "${topo.ulaPrefix}:${toString vid}::/64";
      in
      (r.dst or "") == tenantPrefix;

  sanitizeTenantRoutes =
    iface:
    if vid == null then
      iface
    else
      iface
      // {
        routes4 = builtins.filter keepRoute4 (iface.routes4 or [ ]);
        routes6 = builtins.filter keepRoute6 (iface.routes6 or [ ]);
      };

  rewriteVlanId =
    iface:
    if vid != null && iface.kind == "p2p" && iface.vlanId != null then
      iface // { vlanId = iface.vlanId + vid; }
    else
      iface;

  directIfaces = lib.mapAttrs (
    _lname: l:
    let
      ep = (l.endpoints or { }).${nodeName} or { };
    in
    sanitizeTenantRoutes (mkIfaceFrom l ep)
  ) directLinks;

  inheritedIfaces = lib.mapAttrs (
    _lname: l:
    let
      ep = (l.endpoints or { }).${fabricHost} or { };
    in
    sanitizeTenantRoutes (rewriteVlanId (mkIfaceFrom l ep))
  ) inheritedP2pLinks;

  interfaces = inheritedIfaces // directIfaces;

in
sanitize {
  node = nodeName;
  interfaces = interfaces;
}
