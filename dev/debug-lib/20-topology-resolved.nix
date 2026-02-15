{ cfg }:

let
  common = import ./common.nix { inherit cfg; };
  inherit (common) lib;

  raw = import ./10-topology-raw.nix { inherit cfg; };
in
import ../../lib/topology/20-topology-resolved.nix {
  inherit lib cfg raw;
}
