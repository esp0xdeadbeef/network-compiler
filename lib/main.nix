{ lib }:

inputs:

let
  stages = import ./stages.nix { inherit lib; };

  result = stages.run inputs;

  flake = builtins.getFlake (toString ../.);

  meta = {
    compiler = {
      gitRev = if flake ? rev then flake.rev else "dirty";

      gitDirty = if flake ? dirtyRev then true else false;
    };
  };

in
result // { inherit meta; }
