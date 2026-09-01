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
      ] tenantNames serviceIndex overlayNames uplinkNames (relation.from or { });

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
    }
    // lib.optionalAttrs (relation ? returnBehavior) {
      inherit (relation) returnBehavior;
    }
    // lib.optionalAttrs (relation ? publicIngressTupleAuthority) {
      inherit (relation) publicIngressTupleAuthority;
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

  guards = import ./relations/guards.nix {
    inherit
      lib
      util
      keys
      sortRelations
      ;
  };
in
{
  inherit
    normalizeRelationWithProvenance
    sortRelations
    ;
  inherit (guards)
    ensureNoConflictingRelations
    ensureHasExternalAllow
    ;
}
