{ cfg }:

let
  common = import ./common.nix { inherit cfg; };
  inherit (common) lib;

  eval = import ../../lib/eval.nix { inherit lib; };
  routed = eval cfg;

  q = import ../../lib/query/summary.nix { inherit lib routed; };
in
q
