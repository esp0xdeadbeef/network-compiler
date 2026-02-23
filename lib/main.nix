{ lib, self }:

inputs:

let
  stages = import ./stages.nix { inherit lib; };

  result = stages.run inputs;

  gitRev = if self ? rev then self.rev else "dirty";

  gitDirty = if self ? dirtyRev then true else false;

  meta = {
    compiler = {
      inherit gitRev gitDirty;
    };
  };

in
result // { inherit meta; }
