{ path }:

let
  flake = builtins.getFlake (toString ./.);
  pkgs = import flake.inputs.nixpkgs { system = builtins.currentSystem; };
  lib = pkgs.lib;

  inputs = import path;

  compile = import ../lib/main.nix { inherit lib; };

  result = compile inputs;

in
builtins.toJSON result
