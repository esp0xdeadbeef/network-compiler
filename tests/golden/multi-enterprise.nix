let
  lib = import <nixpkgs/lib>;
  compiler = import ../../lib { inherit lib; };
  input = import ../fixtures/multi-enterprise.nix;
in
compiler.compile input
