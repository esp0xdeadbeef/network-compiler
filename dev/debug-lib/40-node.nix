{
  cfg,
  nodeName ? null,
}:

let
  common = import ./common.nix { inherit cfg; };
  inherit (common) lib;

  eval = import ../../lib/eval.nix { inherit lib; };
  routed = eval cfg;

  q = import ../../lib/query/node.nix { inherit lib routed; };

  chosen =
    if nodeName != null then
      nodeName
    else
      routed.coreRoutingNodeName or cfg.coreNodeName or "s-router-core";
in
q chosen
