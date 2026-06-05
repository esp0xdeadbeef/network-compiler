{ lib }:

let
  util = import ../util.nix { inherit lib; };
  subjects = import ./subjects.nix { inherit lib; };
  target = import ./target.nix { inherit lib; };
  keys = import ./keys.nix { inherit lib; };
  indexes = import ./indexes.nix { inherit lib; };
  inherit (util) ensure throwError;
  inherit (subjects) normalizeSubject;
  inherit (target) normalizeTarget;
  inherit (keys) subjectKey targetKey;
  inherit (indexes) trafficTypeDef;

  mkRelationSource = idx: relation: from: to: trafficType: action: {
    kind = "relation";
    id =
      if relation ? id then
        relation.id
      else
        "relation:${subjectKey from}->${targetKey to}:${trafficType}:${action}:${
        toString (relation.priority or 0)
      }";
    priority = relation.priority or 0;
    sourceAudit = {
      outputPath = [
        "relations"
        idx
      ];
      sourceClass = "user-intent";
      sourcePath = [
        "communicationContract"
        "relations"
        idx
      ];
      authority = "network-compiler";
    };
  };

  normalizeRelationWithProvenance =
    siteKey: overlayNames: uplinkNames: tenantNames: serviceIndex: trafficTypeIndex: idx: relation:
    let
      from = normalizeSubject siteKey idx [
        "communicationContract"
        "relations"
        idx
        "from"
      ]
        tenantNames
        serviceIndex
        overlayNames
        uplinkNames
        (relation.from or { });

      to = normalizeTarget siteKey idx tenantNames serviceIndex overlayNames uplinkNames (
        relation.to or null
      );

      action = relation.action or "deny";

      _action =
        ensure
          (builtins.elem action [
            "allow"
            "deny"
          ])
          {
            code = "E_CONTRACT_ACTION";
            site = siteKey;
            path = [
              "communicationContract"
              "relations"
              idx
              "action"
            ];
            message = "relation.action must be 'allow' or 'deny'";
            hints = [ "Set action = \"allow\" or action = \"deny\"." ];
          };

      trafficTypeName = relation.trafficType or "any";
      trafficType = trafficTypeDef siteKey idx trafficTypeIndex trafficTypeName;

      source = mkRelationSource idx relation from to trafficType.name action;
    in
    {
      inherit
        source
        from
        to
        action
        ;
      trafficType = trafficType.name;
      match = trafficType.match;
    };

  sortRelations =
    relations:
    let
      cmp =
        a: b:
        if a.source.priority < b.source.priority then
          true
        else if a.source.priority > b.source.priority then
          false
        else if a.source.id < b.source.id then
          true
        else if a.source.id > b.source.id then
          false
        else if a.trafficType < b.trafficType then
          true
        else if a.trafficType > b.trafficType then
          false
        else
          a.action < b.action;
    in
    lib.sort cmp relations;

  relationFromIsInternal =
    relation:
    builtins.isAttrs relation.from
    && builtins.elem (relation.from.kind or null) [
      "tenant"
      "tenant-set"
    ];

  relationToIsExternal =
    relation: builtins.isAttrs relation.to && (relation.to.kind or null) == "external";

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
      (builtins.any
        (
          r: (r.action or null) == "allow" && relationFromIsInternal r && relationToIsExternal r
        )
        relations)
      {
        code = "E_CONTRACT_MISSING_EXTERNAL_ALLOW";
        site = siteKey;
        path = [
          "communicationContract"
          "relations"
        ];
        message = "every site must declare at least one allow relation from an internal subject to an external network";
        hints = [
          "Add a relation like { from = { kind = \"tenant\"; name = \"mgmt\"; }; to = { kind = \"external\"; name = \"wan\"; }; trafficType = \"any\"; action = \"allow\"; }."
        ];
      };
in
{
  inherit
    normalizeRelationWithProvenance
    sortRelations
    ensureNoConflictingRelations
    ensureHasExternalAllow
    ;
}
