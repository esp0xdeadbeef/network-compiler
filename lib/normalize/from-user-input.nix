{ lib }:

site:

let
  util = import ../correctness/util.nix { inherit lib; };
  attachmentRef = import ./attachment-ref.nix { inherit lib; };

  topo =
    if site ? topology && builtins.isAttrs site.topology then
      site.topology
    else
      util.throwError {
        code = "E_INPUT_MISSING_TOPOLOGY";
        site = site.siteName or null;
        path = [ "topology" ];
        message = "site.topology is required";
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

  accessUnits =
    let
      names = builtins.attrNames units;
      isAccess = n: ((units.${n}.role or null) == "access");
    in
    lib.filter isAccess names;

  ownership = site.ownership or { };
  prefixes = ownership.prefixes or [ ];
  endpoints = ownership.endpoints or [ ];

  isTenantPrefix = p: builtins.isAttrs p && (p.kind or null) == "tenant" && (p.name or null) != null;

  tenants = map (
    p:
    {
      name = p.name;
      ipv4 = p.ipv4 or null;
      ipv6 = p.ipv6 or null;
    }
    // lib.optionalAttrs (p ? ra6Prefixes) {
      ra6Prefixes = p.ra6Prefixes;
    }
    // lib.optionalAttrs (p ? routedPrefixes) {
      routedPrefixes = p.routedPrefixes;
    }
  ) (lib.filter isTenantPrefix prefixes);

  isHostEndpoint = e: builtins.isAttrs e && (e.kind or null) == "host" && (e.name or null) != null;

  hosts = map (e: {
    name = e.name;
    tenant = e.tenant or null;
  }) (lib.filter isHostEndpoint endpoints);

  segments = {
    tenants = tenants;
    services = [ ];
  };

  segRef = seg: attachmentRef { inherit site util seg; };

  attachments = lib.concatMap (
    unit:
    map (a: {
      inherit unit;
      segment = segRef a;
    }) (units.${unit}.attachments or [ ])
  ) accessUnits;

  transitLinks = topo.links or [ ];

  pools = site.pools or { };

  transitPool = if pools ? p2p then pools.p2p else null;

  localPool = if pools ? loopback then pools.loopback else null;

in
{
  enterprise = site.enterprise or "default";

  inherit
    segments
    attachments
    hosts
    ;

  transit = {
    links = transitLinks;
    pool = transitPool;
  };

  addressPools = {
    p2p = transitPool;
    local = localPool;
  };
}
