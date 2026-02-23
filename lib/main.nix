{ lib }:

inputs:

let
  stages = import ./stages.nix { inherit lib; };
in
stages.run inputs
