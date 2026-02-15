{ cfg }:

let
  common = import ./common.nix { inherit cfg; };
  inherit (common) lib;

  all = import ./90-all.nix { inherit cfg; };
  topoRaw = import ./10-topology-raw.nix { inherit cfg; };
in
import ../../lib/render/70-render-networkd.nix {
  inherit
    lib
    cfg
    all
    topoRaw
    ;
}
