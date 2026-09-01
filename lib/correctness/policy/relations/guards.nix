{
  lib,
  util,
  keys,
  sortRelations,
}:

let
  inherit (util) ensure throwError;
  inherit (keys) subjectKey targetKey;

  relationFromIsInternal =
    relation:
    builtins.isAttrs relation.from
    && builtins.elem (relation.from.kind or null) [
      "tenant"
      "tenant-set"
    ];

  relationToIsExternal =
    relation: builtins.isAttrs relation.to && (relation.to.kind or null) == "external";

  relationIsExplicitPublicIngress =
    relation:
    (relation.action or null) == "allow"
    && builtins.isAttrs relation.from
    && (relation.from.kind or null) == "external"
    && builtins.isAttrs relation.to
    && (relation.to.kind or null) == "service"
    && builtins.isAttrs (relation.publicIngressTupleAuthority or null);

  relationConflictKey =
    relation: "${subjectKey relation.from}->${targetKey relation.to}:${relation.trafficType}";

  ensureNoConflictingRelations =
    siteKey: relations:
    let
      sorted = sortRelations relations;

      step =
        state: relation:
        let
          key = relationConflictKey relation;
          prev = state.${key} or null;
        in
        if prev == null then
          state // { "${key}" = relation.action; }
        else if prev == relation.action then
          state
        else
          throwError {
            code = "E_CONTRACT_CONFLICTING_RELATIONS";
            site = siteKey;
            path = [
              "communicationContract"
              "relations"
            ];
            message = "conflicting relations for '${key}'";
            hints = [ "Do not declare both allow and deny for the same normalized relation." ];
          };

      _visited = builtins.foldl' step { } sorted;
    in
    true;

  ensureHasExternalAllow =
    siteKey: relations:
    ensure
      (
        builtins.any (
          r: (r.action or null) == "allow" && relationFromIsInternal r && relationToIsExternal r
        ) relations
        || builtins.any relationIsExplicitPublicIngress relations
      )
      {
        code = "E_CONTRACT_MISSING_EXTERNAL_ALLOW";
        site = siteKey;
        path = [
          "communicationContract"
          "relations"
        ];
        message = "every site must declare either an internal-to-external allow or an explicit public-ingress authority";
        hints = [
          "Add an authorized internal-to-external relation, or for an ingress-only site add an external-to-service allow with publicIngressTupleAuthority."
        ];
      };
in
{
  inherit
    ensureNoConflictingRelations
    ensureHasExternalAllow
    ;
}
