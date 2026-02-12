{
  sopsData ? { },
}:
let
  pkgs = null;
  flake = builtins.getFlake (toString ../../.);
  lib = flake.lib;

  cfg = import ./inputs.nix { inherit sopsData; };

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
      inherit lib pkgs;
      inherit (cfg) ulaPrefix tenantV4Base;
    } n routed
  ) routed.nodes;

  wan = import ./50-wan.nix { inherit sopsData; };
  multiWan = import ./60-multi-wan.nix { inherit sopsData; };
}
