{ lib }:

let
  indexes = import ./policy/indexes.nix { inherit lib; };
  relations = import ./policy/relations.nix { inherit lib; };
in
{
  inherit (indexes)
    buildTrafficTypeIndex
    buildServiceIndex
    ;
  inherit (relations)
    normalizeRelationWithProvenance
    sortRelations
    ensureNoConflictingRelations
    ensureHasExternalAllow
    ;
}
