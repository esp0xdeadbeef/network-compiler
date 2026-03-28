let
  lib = import <nixpkgs/lib>;
  compiler = import ../../lib { inherit lib; };
  input = import ../fixtures/priority-stability.nix;
in
compiler.compile input
