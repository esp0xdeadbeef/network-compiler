{ lib }:

let
  util = import ./util.nix { inherit lib; };
  inherit (util) ensure assertUnique throwError;

  normalizeMatch =
    idx: trafficTypeName: m:
    let
      proto =
        if builtins.isAttrs m && m ? proto then
          m.proto
        else if builtins.isAttrs m && m ? l4 then
          m.l4
        else
          "any";

      family =
        if builtins.isAttrs m && m ? family then
          m.family
        else if builtins.isAttrs m && m ? families then
          let
            fs = m.families;
          in
          if fs == [ ] then "any" else builtins.elemAt fs 0
        else
          "any";

      dports = if builtins.isAttrs m && m ? dports then m.dports else [ ];
    in
    {
      inherit proto family dports;
    };

  buildTrafficTypeIndex =
    communicationContract:
    let
      trafficTypes = communicationContract.trafficTypes or [ ];

      _uniqTrafficTypes = assertUnique "traffic type name" (map (t: t.name) trafficTypes);

      normalizeOne = t: {
        name = t.name;
        match = lib.imap0 (idx: m: normalizeMatch idx t.name m) (t.match or [ ]);
      };
    in
    builtins.listToAttrs (
      map (t: {
        name = t.name;
        value = normalizeOne t;
      }) trafficTypes
    );

  trafficTypeDef =
    siteKey: idx: trafficTypeIndex: trafficTypeName:
    if trafficTypeName == "any" then
      {
        name = "any";
        match = [
          {
            proto = "any";
            family = "any";
            dports = [ ];
          }
        ];
      }
    else if builtins.hasAttr trafficTypeName trafficTypeIndex then
      trafficTypeIndex.${trafficTypeName}
    else
      throwError {
        code = "E_CONTRACT_UNKNOWN_TRAFFIC_TYPE";
        site = siteKey;
        path = [
          "communicationContract"
          "relations"
          idx
          "trafficType"
        ];
        message = "relation references unknown trafficType '${trafficTypeName}'";
        hints = [ "Declare trafficTypes = [ { name = \"${trafficTypeName}\"; match = ...; } ]." ];
      };

  buildServiceIndex =
    communicationContract:
    let
      services = communicationContract.services or [ ];
      _uniqServices = assertUnique "service name" (map (s: s.name) services);
    in
    builtins.listToAttrs (
      map (s: {
        name = s.name;
        value = s;
      }) services
    );

  normalizeSubject =
    siteKey: idx: path: tenantNames: externals: subj:
    let
      _shape = ensure (builtins.isAttrs subj) {
        code = "E_CONTRACT_SUBJECT_SHAPE";
        site = siteKey;
        path = path;
        message = "subject must be an attrset";
        hints = [
          "Use { kind = \"tenant\"; name = \"...\"; }."
          "Or use { kind = \"tenant-set\"; members = [ ... ]; }."
          "Or use { kind = \"external\"; name = \"wan\"; }."
        ];
      };

      kind = subj.kind or null;

      _kind =
        ensure
          (builtins.elem kind [
            "tenant"
            "tenant-set"
            "external"
          ])
          {
            code = "E_CONTRACT_SUBJECT_KIND";
            site = siteKey;
            path = path ++ [ "kind" ];
            message = "subject.kind must be 'tenant', 'tenant-set', or 'external'";
            hints = [
              "Use kind = \"tenant\"."
              "Or kind = \"tenant-set\"."
              "Or kind = \"external\"."
            ];
          };
    in
    if kind == "tenant" then
      let
        name = subj.name or null;

        _name = ensure (name != null && builtins.isString name && name != "") {
          code = "E_CONTRACT_SUBJECT_NAME";
          site = siteKey;
          path = path ++ [ "name" ];
          message = "tenant subject requires a non-empty name";
          hints = [ "Set name = \"<tenant-name>\"." ];
        };

        _exists = ensure (builtins.elem name tenantNames) {
          code = "E_CONTRACT_UNKNOWN_TENANT";
          site = siteKey;
          path = path ++ [ "name" ];
          message = "relation references unknown tenant '${name}'";
          hints = [ "Declare tenant '${name}' under ownership.prefixes." ];
        };
      in
      {
        kind = "tenant";
        inherit name;
      }
    else if kind == "tenant-set" then
      let
        members = subj.members or [ ];

        _membersShape =
          ensure (builtins.isList members && builtins.all builtins.isString members && members != [ ])
            {
              code = "E_CONTRACT_SUBJECT_MEMBERS";
              site = siteKey;
              path = path ++ [ "members" ];
              message = "tenant-set subject requires a non-empty members list";
              hints = [ "Set members = [ \"tenant-a\" \"tenant-b\" ]." ];
            };

        _membersExist = builtins.all (name: builtins.elem name tenantNames) members;

        _exists = ensure _membersExist {
          code = "E_CONTRACT_UNKNOWN_TENANT";
          site = siteKey;
          path = path ++ [ "members" ];
          message = "tenant-set includes unknown tenant";
          hints = [ "Ensure every tenant-set member exists under ownership.prefixes." ];
        };
      in
      {
        kind = "tenant-set";
        members = lib.sort builtins.lessThan members;
      }
    else
      let
        name = subj.name or null;

        _name = ensure (name != null && builtins.isString name && name != "") {
          code = "E_CONTRACT_SUBJECT_NAME";
          site = siteKey;
          path = path ++ [ "name" ];
          message = "external subject requires a non-empty name";
          hints = [ "Set name = \"<uplink-or-overlay-name>\"." ];
        };

        _exists = ensure (builtins.elem name externals) {
          code = "E_CONTRACT_UNKNOWN_EXTERNAL";
          site = siteKey;
          path = path ++ [ "name" ];
          message = "relation references unknown external '${name}'";
          hints = [
            "Declare an uplink under topology.nodes.<core>.uplinks.<name>."
            "Or declare a transport overlay with transport.overlays[].name."
          ];
        };
      in
      {
        kind = "external";
        inherit name;
      };

  normalizeTarget =
    siteKey: idx: tenantNames: serviceIndex: externals: target:
    let
      basePath = [
        "communicationContract"
        "relations"
        idx
        "to"
      ];
    in
    if target == "any" then
      "any"
    else
      let
        _shape = ensure (builtins.isAttrs target) {
          code = "E_CONTRACT_TARGET_SHAPE";
          site = siteKey;
          path = basePath;
          message = "relation.to must be \"any\" or an attrset";
          hints = [
            "Use \"any\"."
            "Or use { kind = \"external\"; name = \"wan\"; }."
            "Or use { kind = \"service\"; name = \"dns\"; }."
            "Or use { kind = \"tenant\"; name = \"mgmt\"; }."
          ];
        };

        kind = target.kind or null;

        _kind =
          ensure
            (builtins.elem kind [
              "tenant"
              "tenant-set"
              "service"
              "external"
            ])
            {
              code = "E_CONTRACT_TARGET_KIND";
              site = siteKey;
              path = basePath ++ [ "kind" ];
              message = "relation.to.kind must be tenant, tenant-set, service, or external";
              hints = [ "Set kind to a supported target kind." ];
            };
      in
      if
        builtins.elem kind [
          "tenant"
          "tenant-set"
        ]
      then
        normalizeSubject siteKey idx basePath tenantNames externals target
      else if kind == "service" then
        let
          name = target.name or null;

          _name = ensure (name != null && builtins.isString name && name != "") {
            code = "E_CONTRACT_TARGET_NAME";
            site = siteKey;
            path = basePath ++ [ "name" ];
            message = "service target requires a non-empty name";
            hints = [ "Set name = \"<service-name>\"." ];
          };

          _exists = ensure (builtins.hasAttr name serviceIndex) {
            code = "E_CONTRACT_UNKNOWN_SERVICE";
            site = siteKey;
            path = basePath ++ [ "name" ];
            message = "relation references unknown service '${name}'";
            hints = [ "Declare service '${name}' under communicationContract.services." ];
          };
        in
        {
          kind = "service";
          inherit name;
        }
      else
        let
          name = target.name or null;

          _name = ensure (name != null && builtins.isString name && name != "") {
            code = "E_CONTRACT_TARGET_NAME";
            site = siteKey;
            path = basePath ++ [ "name" ];
            message = "external target requires a non-empty name";
            hints = [ "Set name = \"<uplink-or-overlay-name>\"." ];
          };

          _exists = ensure (builtins.elem name externals) {
            code = "E_CONTRACT_UNKNOWN_EXTERNAL";
            site = siteKey;
            path = basePath ++ [ "name" ];
            message = "relation references unknown external '${name}'";
            hints = [
              "Declare an uplink under topology.nodes.<core>.uplinks.<name>."
              "Or declare a transport overlay with transport.overlays[].name."
            ];
          };
        in
        {
          kind = "external";
          inherit name;
        };

  subjectKey =
    subj:
    if subj.kind == "tenant" then
      "tenant:${subj.name}"
    else if subj.kind == "tenant-set" then
      "tenant-set:${lib.concatStringsSep "," (lib.sort builtins.lessThan subj.members)}"
    else
      "external:${subj.name}";

  targetKey =
    target:
    if target == "any" then
      "any"
    else if target.kind == "service" then
      "service:${target.name}"
    else
      subjectKey target;

  mkRelationSource = relation: from: to: trafficType: action: {
    kind = "relation";
    id =
      if relation ? id then
        relation.id
      else
        "relation:${subjectKey from}->${targetKey to}:${trafficType}:${action}:${
          toString (relation.priority or 0)
        }";
    priority = relation.priority or 0;
  };

  normalizeRelationWithProvenance =
    siteKey: externals: tenantNames: serviceIndex: trafficTypeIndex: idx: relation:
    let
      from = normalizeSubject siteKey idx [
        "communicationContract"
        "relations"
        idx
        "from"
      ] tenantNames externals (relation.from or { });

      to = normalizeTarget siteKey idx tenantNames serviceIndex externals (relation.to or null);

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

      source = mkRelationSource relation from to trafficType.name action;
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
      (builtins.any (
        r: (r.action or null) == "allow" && relationFromIsInternal r && relationToIsExternal r
      ) relations)
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
    buildTrafficTypeIndex
    buildServiceIndex
    normalizeRelationWithProvenance
    sortRelations
    ensureNoConflictingRelations
    ensureHasExternalAllow
    ;
}
