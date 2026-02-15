{
  sopsData ? { },
}:
let
  common = import ./common.nix { inherit sopsData; };
  inherit (common) lib;

  routed = import ./30-routing.nix { inherit sopsData; };
  q = import ../../lib/query/routing-table.nix { inherit lib; };
in
q routed
