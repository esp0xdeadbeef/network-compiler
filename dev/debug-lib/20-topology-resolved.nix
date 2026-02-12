{
  sopsData ? { },
}:
let
  pkgs = null;
  flake = builtins.getFlake (toString ../../.);
  lib = flake.lib;
  cfg = import ./inputs.nix { inherit sopsData; };

  raw = import ./10-topology-raw.nix { inherit sopsData; };
in
import ../../lib/topology-resolve.nix {
  inherit lib;
  inherit (cfg) ulaPrefix tenantV4Base;
} raw
