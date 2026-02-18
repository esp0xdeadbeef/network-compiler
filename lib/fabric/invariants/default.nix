{ lib }:

let
  nodeRoles = import ./node-roles.nix { inherit lib; };
  userSpaceDisjoint = import ./user-space-disjoint.nix { inherit lib; };
  globalUserSpace = import ./global-user-space-disjoint.nix { inherit lib; };
  globalP2PPool = import ./global-p2p-pool-disjoint.nix { inherit lib; };
in
{
  checkSite =
    { site }:
    let
      _roles = nodeRoles.check {
        nodes = site.nodes or { };
      };

      _user = userSpaceDisjoint.check {
        inherit site;
      };

      _poolPresence =
        if !(site ? p2p-pool) then throw "invariants: missing required attribute 'p2p-pool'" else true;
    in
    true;

  checkAll =
    { sites }:
    let
      a = globalUserSpace.check { inherit sites; };
      b = globalP2PPool.check { inherit sites; };
    in
    builtins.deepSeq [ a b ] true;
}
