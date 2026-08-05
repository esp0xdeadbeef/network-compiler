{
  lib,
  localRaw,
  helpers,
}:

let
  nonEmptyString = value: builtins.isString value && value != "";
  listOrEmpty = value: if builtins.isList value then value else [ ];
  warning = code: relation: context: {
    traceId =
      if code == "DNS_LOCAL_ONLY_AUTHORITY_LEAK" then
        "FS-540-HDS-010-SDS-010-SMS-020"
      else
        "FS-560-HDS-010-SDS-020-SMS-010";
    inherit code context;
    requester = "service:${toString ((relation.requester or { }).service or "<missing>")}";
    resolverService = toString ((relation.authority or { }).service or "<missing>");
    candidateIds = [ (toString ((relation.relation or { }).id or "<missing>")) ];
    disposition = "fail-closed";
  };
  evaluate = relation:
    let
      authority = relation.authority or { };
      requester = relation.requester or { };
      relationContract = relation.relation or { };
      provider = relation.providerPolicy or { };
      lateral = relation.lateralPolicy or { };
      namespaces = listOrEmpty (requester.allowedNamespaces or null);
      missingIdentity =
        !nonEmptyString (authority.service or null)
        || !nonEmptyString (requester.service or null)
        || !nonEmptyString (relationContract.id or null)
        || namespaces == [ ]
        || builtins.any (namespace: !nonEmptyString namespace) namespaces;
      leaks =
        (requester.recursion or false)
        || (requester.publicFallback or false)
        || (lateral.recursion or false)
        || (lateral.transitiveEgress or false)
        || (provider.action or null) != "refuse_non_local"
        || (lateral.action or null) != "refuse_non_local";
      warnings =
        lib.optional missingIdentity (warning "DNS_LOCAL_SHARING_BINDING_INCOMPLETE" relation "relationship-identity")
        ++ lib.optional leaks (warning "DNS_LOCAL_ONLY_AUTHORITY_LEAK" relation "local-only-authority");
    in
    { inherit relation warnings; active = warnings == [ ]; };
  evaluations = map evaluate localRaw;
  activeRelations = map (entry: entry.relation) (lib.filter (entry: entry.active) evaluations);
  relationIds = map (relation: (relation.relation or { }).id or "<missing>") activeRelations;
  duplicateIds = lib.filter
    (relationId: builtins.length (lib.filter (candidate: candidate == relationId) relationIds) > 1)
    (lib.unique relationIds);
  duplicateWarnings = map
    (relationId: {
      traceId = "FS-560-HDS-010-SDS-020-SMS-010";
      code = "DNS_LOCAL_SHARING_RELATION_DUPLICATE";
      requester = "local-namespace-sharing";
      resolverService = "local-namespace-sharing";
      candidateIds = [ relationId ];
      context = "relation-identity";
      disposition = "fail-closed";
    })
    duplicateIds;
  warnings = helpers.sortRecords (lib.concatMap (entry: entry.warnings) evaluations ++ duplicateWarnings);
in
{
  inherit warnings;
  normalized = if warnings != [ ] then [ ] else helpers.sortRecords activeRelations;
}
