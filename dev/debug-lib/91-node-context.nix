{
  cfg,
  nodeName ? null,
  linkName ? null,
}:

let
  common = import ./common.nix { inherit cfg; };
  inherit (common) lib;

  all = import ./90-all.nix { };
  routed = import ./30-routing.nix { inherit cfg; };

  q = import ../../lib/query/node-context.nix { inherit lib; };

  fabricHost =
    if cfg ? coreNodeName && builtins.isString cfg.coreNodeName then
      cfg.coreNodeName
    else
      throw "debug-lib/91-node-context: missing required cfg.coreNodeName (no internal default)";
in
q {
  inherit
    all
    routed
    nodeName
    linkName
    ;
  inherit fabricHost;
}
