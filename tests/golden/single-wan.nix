let
  lib = import <nixpkgs/lib>;
  compiler = import ../../lib { inherit lib; };
  input = import ../fixtures/single-uplink.nix;
in
compiler.compile input
