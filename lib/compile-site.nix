{ lib }:

site:

let
  alloc = import ./p2p/alloc.nix { inherit lib; };
  invariants = import ./fabric/invariants.nix { inherit lib; };

  links = alloc.alloc {
    p2p = site.p2p-pool;
    links = site.links;
  };

  networks = lib.mapAttrs (_: n: n.networks or null) (
    lib.filterAttrs (_: n: (n.role or "") == "access") site.nodes
  );

  _checked = invariants.checkSite { inherit site links; };

in
{
  inherit (site) nodes;
  inherit links networks;
}
