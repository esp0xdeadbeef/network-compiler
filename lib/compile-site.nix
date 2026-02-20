{ lib }:

site:

let
  alloc = import ./p2p/alloc.nix { inherit lib; };
  invariants = import ./fabric/invariants { inherit lib; };

  _shape =
    if !(site ? nodes && builtins.isAttrs site.nodes) then
      throw "compile-site: site.nodes must be an attribute set"
    else if !(site ? links && builtins.isList site.links) then
      throw "compile-site: site.links must be a list of node pairs"
    else if !(site ? p2p-pool && builtins.isAttrs site.p2p-pool) then
      throw "compile-site: missing required attribute 'p2p-pool'"
    else if !(site.p2p-pool ? ipv4) then
      throw "compile-site: p2p-pool.ipv4 is required"
    else
      true;

  _inv = invariants.checkSite { inherit site; };

  links = alloc.alloc { inherit site; };

  emptyNode = n: n // { interfaces = { }; };

  nodes0 = lib.mapAttrs (_: emptyNode) site.nodes;

  addIface =
    nodeName: linkName: iface:
    lib.mapAttrs (
      n: node:
      if n == nodeName then
        node
        // {
          interfaces = node.interfaces // {
            ${linkName} = iface;
          };
        }
      else
        node
    );

  nodesWithIfaces = lib.foldlAttrs (
    nodesAcc: linkName: link:
    let
      epNames = builtins.attrNames link.endpoints;

      a = builtins.elemAt epNames 0;
      b = builtins.elemAt epNames 1;

      aData = link.endpoints.${a};
      bData = link.endpoints.${b};

      nodes1 = addIface a linkName {
        peer = b;
        kind = link.kind;
        addr4 = aData.addr4 or null;
        addr6 = aData.addr6 or null;
      } nodesAcc;

      nodes2 = addIface b linkName {
        peer = a;
        kind = link.kind;
        addr4 = bData.addr4 or null;
        addr6 = bData.addr6 or null;
      } nodes1;

    in
    nodes2
  ) nodes0 links;

  result = {
    nodes = nodesWithIfaces;
    inherit links;
  };

in
assert _shape;
assert _inv;
builtins.deepSeq result result
