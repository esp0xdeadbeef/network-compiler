{ cfg }:

let
  common = import ./common.nix { inherit cfg; };
  inherit (common) lib;
in
import ../../lib/10-topology-raw.nix {
  inherit lib cfg;
}
