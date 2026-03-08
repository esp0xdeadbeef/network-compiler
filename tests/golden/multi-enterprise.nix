let
  lib = import <nixpkgs/lib>;
  compiler = import ../.. { inherit lib; };
  input = import ../../examples/multi-enterprise/inputs.nix;
in
compiler.run input
