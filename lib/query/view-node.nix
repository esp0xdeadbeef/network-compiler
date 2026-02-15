# ./lib/query/view-node.nix
{ lib }:

nodeName: topo:

let
  links = lib.filterAttrs (_: l: lib.elem nodeName (l.members or [ ])) (topo.links or { });

  sanitize = import ./sanitize.nix { inherit lib; };

  getTenantVid =
    ep:
    if ep ? tenant && builtins.isAttrs ep.tenant && ep.tenant ? vlanId then ep.tenant.vlanId else null;

in
sanitize {
  node = nodeName;

  interfaces = lib.mapAttrs (
    _lname: l:
    let
      ep = (l.endpoints or { }).${nodeName} or { };
    in
    {
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
    }
  ) links;
}

