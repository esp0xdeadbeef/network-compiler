let
  lib = import <nixpkgs/lib>;
  compiler = import ../.. { inherit lib; };
  input = import ../../examples/priority-stability/inputs.nix;
in
compiler.run input
