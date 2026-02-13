{ lib }:

topo:

let
  a1 = import ./default-route-mode.nix { inherit lib; } topo;
  a2 = import ./default-route-wan-consistency.nix { inherit lib; } topo;
in
{
  assertions = (a1.assertions or [ ]) ++ (a2.assertions or [ ]);
}
