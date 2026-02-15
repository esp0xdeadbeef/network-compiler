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
in
q {
  inherit
    all
    routed
    nodeName
    linkName
    ;
  fabricHost = "s-router-core";
}
