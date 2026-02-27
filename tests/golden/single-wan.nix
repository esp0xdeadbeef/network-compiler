let
  lib = import <nixpkgs/lib>;
  compiler = import ../.. { inherit lib; };
  input = import ../../examples/single-wan/inputs.nix;
in
compiler.run input
