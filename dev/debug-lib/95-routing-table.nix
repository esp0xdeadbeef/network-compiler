{ cfg }:

let
  common = import ./common.nix { inherit cfg; };
  inherit (common) lib;

  eval = import ../../lib/eval.nix { inherit lib; };
  routed = eval cfg;

in
import ../../lib/query/routing-table.nix { inherit lib routed; }
