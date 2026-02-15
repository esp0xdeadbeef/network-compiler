{
  sopsData ? { },
}:
let
  common = import ./common.nix { inherit sopsData; };
  inherit (common) lib cfg;

  routed = import ./30-routing.nix { inherit sopsData; };
in
{
  topology = {
    domain = routed.domain;
    nodes = builtins.attrNames routed.nodes;
    links = builtins.attrNames routed.links;
  };

  nodes = builtins.mapAttrs (
    n: _:
    import ./view-node.nix {
      inherit lib;
      inherit (cfg) ulaPrefix tenantV4Base;
    } n routed
  ) routed.nodes;

  wan = import ./50-wan.nix { inherit sopsData; };
  multiWan = import ./60-multi-wan.nix { inherit sopsData; };
}
