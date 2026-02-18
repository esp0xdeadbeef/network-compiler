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

  result = {
    inherit (site) nodes;
    inherit links;
  };

in
assert _shape;
assert _inv;
builtins.deepSeq links result
