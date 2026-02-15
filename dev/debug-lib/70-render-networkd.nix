{
  sopsData ? { },
}:
let
  common = import ./common.nix { inherit sopsData; };
  inherit (common) lib;

  all = import ./90-all.nix { inherit sopsData; };
  topoRaw = import ./10-topology-raw.nix { inherit sopsData; };

  renderer = import ../../lib/render/networkd/default.nix { inherit lib; };
in
renderer.render {
  inherit all;
  topologyRaw = topoRaw;
  nodeName = "s-router-access-10";
}
