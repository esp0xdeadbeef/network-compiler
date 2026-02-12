{
  lib,
  ulaPrefix,
  tenantV4Base,
}:

topoRaw:

let
  links = topoRaw.links or { };
  nodes = topoRaw.nodes or { };

  getEp = l: n: (l.endpoints or { }).${n} or { };

  mkIface =
    linkName: l: nodeName:
    let
      ep = getEp l nodeName;
    in
    {
      # link identity
      kind = l.kind or null;
      carrier = l.carrier or "lan";
      vlanId = l.vlanId or null;

      # endpoint data
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
    lib.filter (lname: lib.elem nodeName ((links.${lname}.members or [ ]))) (lib.attrNames links);

  interfacesForNode =
    nodeName:
    lib.listToAttrs (
      map (lname: {
        name = lname;
        value = mkIface lname links.${lname} nodeName;
      }) (linkNamesForNode nodeName)
    );

  nodes' = lib.mapAttrs (
    n: node:
    node
    // {
      interfaces = interfacesForNode n;
    }
  ) nodes;

in
topoRaw
// {
  inherit ulaPrefix tenantV4Base;
  nodes = nodes';
}
