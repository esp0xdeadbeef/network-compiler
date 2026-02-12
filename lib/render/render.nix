{ lib, compiled }:

let
  networkdModule = import ./networkd/default.nix {
    inherit lib;
  };
in
networkdModule.render compiled
