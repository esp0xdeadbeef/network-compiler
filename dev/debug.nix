{ path }:

let
  flake = builtins.getFlake (toString ./.);
  pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
  lib = pkgs.lib;

  inputs = import path;
  compile = import ../lib/from-inputs.nix { inherit lib; };
in
compile inputs
