{
  sopsData ? { },
  nodeName ? null,
  linkName ? null,
}:
let
  common = import ./common.nix { inherit sopsData; };
  inherit (common) lib;

  all = import ./90-all.nix { inherit sopsData; };
  routed = import ./30-routing.nix { inherit sopsData; };

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
