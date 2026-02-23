{ lib }:

inputs:

let
  stages = import ./stages.nix { inherit lib; };

  result = stages.run inputs;

  flake = builtins.getFlake (toString ../.);

  gitRev =
    if flake ? rev then
      flake.rev
    else if flake ? shortRev then
      flake.shortRev
    else
      "unknown";

  gitDirty = if flake ? dirtyRev then true else false;

  meta = {
    compiler = {
      inherit gitRev gitDirty;
    };
  };

in
result // { inherit meta; }
