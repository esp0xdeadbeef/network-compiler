{ lib }:

# Scope-selection predicates for overlay underlay access (FS-322, FS-460).
#
# Split out of validate-overlay-model.nix to keep that stage under the tracked
# Nix-file LOC soft limit. These helpers answer one question: does the scope a
# tenant attaches to actually select the exit scope the overlay needs?
let
  # A `selects` entry may be a plain scope string or a `{ scope = ...; }`
  # attribute form. FS-322 names scopes, not uplinks, and
  # build-model/fabric/contract-selects.nix normalises both spellings into one
  # target; this reads the same two spellings so a selection that is valid
  # there is not silently unmatchable here.
  selectName =
    entry:
    if builtins.isString entry then
      entry
    else if builtins.isAttrs entry then
      (entry.scope or entry.uplink or null)
    else
      null;

  endpointTenants =
    endpoint:
    if !(builtins.isAttrs endpoint) then
      [ ]
    else if (endpoint.kind or null) == "tenant" then
      [ endpoint.name ]
    else if (endpoint.kind or null) == "tenant-set" then
      endpoint.members or [ ]
    else
      [ ];

  # Does any node carrying this tenant select the given exit scope? A null
  # exit scope only requires that the tenant selects something at all.
  tenantScopeSelects =
    nodes: tenantName: exitName:
    let
      matching = lib.filter (
        nodeName:
        builtins.any (a: (a.kind or null) == "tenant" && (a.name or null) == tenantName) (
          nodes.${nodeName}.attachments or [ ]
        )
      ) (builtins.attrNames nodes);
    in
    if exitName == null then
      builtins.any (nodeName: (nodes.${nodeName}.selects or [ ]) != [ ]) matching
    else
      builtins.any (
        nodeName: builtins.any (s: selectName s == exitName) (nodes.${nodeName}.selects or [ ])
      ) matching;
in
{
  inherit
    endpointTenants
    selectName
    tenantScopeSelects
    ;
}
