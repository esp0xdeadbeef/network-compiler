{ lib }:

site:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;

  topo =
    if site ? topology && builtins.isAttrs site.topology then
      site.topology
    else
      util.throwError {
        code = "E_INPUT_MISSING_TOPOLOGY";
        site = site.siteName or null;
        path = [ "topology" ];
        message = "site.topology is required (legacy inputs removed)";
        hints = [ "Add topology = { nodes = ...; links = ...; } to the site." ];
      };

  units =
    if topo ? nodes && builtins.isAttrs topo.nodes then
      topo.nodes
    else
      util.throwError {
        code = "E_INPUT_MISSING_TOPOLOGY_NODES";
        site = site.siteName or null;
        path = [
          "topology"
          "nodes"
        ];
        message = "site.topology.nodes is required";
        hints = [ "Add topology.nodes = { ... }." ];
      };

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
      _ = ensure (builtins.isAttrs seg) {
        code = "E_INPUT_ATTACHMENT_SHAPE";
        site = site.siteName or null;
        path = [
          "topology"
          "nodes"
        ];
        message = "attachment must be an attrset";
        hints = [ "Use { kind = \"tenant\"; name = \"...\"; }." ];
      };

      kind = seg.kind or null;
      name = seg.name or null;

      _k = ensure (kind != null) {
        code = "E_INPUT_ATTACHMENT_MISSING_KIND";
        site = site.siteName or null;
        path = [
          "topology"
          "nodes"
        ];
        message = "attachment.kind is required";
        hints = [ "Set attachment.kind = \"tenant\" or \"service\"." ];
      };

      _n = ensure (name != null) {
        code = "E_INPUT_ATTACHMENT_MISSING_NAME";
        site = site.siteName or null;
        path = [
          "topology"
          "nodes"
        ];
        message = "attachment.name is required";
        hints = [ "Set attachment.name = \"...\"." ];
      };
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
