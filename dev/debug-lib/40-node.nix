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
    else if routed ? coreRoutingNodeName && routed.coreRoutingNodeName != null then
      routed.coreRoutingNodeName
    else if cfg ? coreNodeName && builtins.isString cfg.coreNodeName then
      cfg.coreNodeName
    else
      throw "debug-lib/40-node: missing required cfg.coreNodeName (no internal default)";
in
q chosen
