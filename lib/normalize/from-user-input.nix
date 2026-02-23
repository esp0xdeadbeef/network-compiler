{ lib }:

site:

let
  assert_ = cond: msg: if cond then true else throw msg;

  topo =
    if site ? topology && builtins.isAttrs site.topology then
      site.topology
    else
      throw "normalize/from-user-input: site.topology is required (legacy inputs removed)";

  units =
    if topo ? nodes && builtins.isAttrs topo.nodes then
      topo.nodes
    else
      throw "normalize/from-user-input: site.topology.nodes is required";

  accessUnit =
    let
      names = builtins.attrNames units;
      isAccess = n: ((units.${n}.role or null) == "access");
      matches = lib.filter isAccess names;
    in
    if builtins.length matches >= 1 then builtins.elemAt matches 0 else null;

  ownership = site.ownership or { };
  prefixes = ownership.prefixes or [ ];

  isTenantPrefix = p: builtins.isAttrs p && (p.kind or null) == "tenant" && (p.name or null) != null;

  tenants = map (p: {
    name = p.name;
    ipv4 = p.ipv4 or null;
    ipv6 = p.ipv6 or null;
  }) (lib.filter isTenantPrefix prefixes);

  segments = {
    tenants = tenants;
    services = [ ];
  };

  segRef =
    seg:
    let
      _ = assert_ (builtins.isAttrs seg) "normalize/from-user-input: attachment must be an attrset";
      kind = seg.kind or null;
      name = seg.name or null;
      _k = assert_ (kind != null) "normalize/from-user-input: attachment.kind is required";
      _n = assert_ (name != null) "normalize/from-user-input: attachment.name is required";
    in
    if kind == "tenant" then
      "tenants:${name}"
    else if kind == "service" then
      "services:${name}"
    else
      "segments:${name}";

  attachments =
    if accessUnit == null then
      [ ]
    else
      map (a: {
        unit = accessUnit;
        segment = segRef a;
      }) (units.${accessUnit}.attachments or [ ]);

  transitLinks = topo.links or [ ];

  pools = site.pools or { };

  transitPool = if pools ? p2p then pools.p2p else null;

  localPool = if pools ? loopback then pools.loopback else null;

in
{
  enterprise = site.enterprise or "default";

  inherit segments attachments;

  transit = {
    links = transitLinks;
    pool = transitPool;
  };

  addressPools = {
    p2p = transitPool;
    local = localPool;
  };
}
