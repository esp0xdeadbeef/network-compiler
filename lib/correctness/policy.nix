{ lib }:

let
  util = import ./util.nix { inherit lib; };
  inherit (util) ensure assertUnique throwError;

  matchListToProto =
    matches:
    let
      ms = if matches == null then [ ] else matches;

      one =
        m:
        let
          l4 = if builtins.isAttrs m && m ? l4 then m.l4 else "any";
          dports = if builtins.isAttrs m && m ? dports then m.dports else [ ];
        in
        if l4 == "any" then
          [ "any" ]
        else if dports == [ ] then
          [ l4 ]
        else
          map (p: "${l4}/${toString p}") dports;
    in
    lib.unique (lib.concatMap one ms);

  buildCapabilityIndex =
    policy:
    let
      catalog = policy.catalog or { };
      services = catalog.services or [ ];

      _uniqServices = assertUnique "service name" (map (s: s.name) services);

      addService =
        acc: svc:
        let
          provides = svc.provides or [ ];
          proto = if svc ? match then matchListToProto svc.match else [ ];
          addCap =
            acc2: capName: if builtins.hasAttr capName acc2 then acc2 else acc2 // { "${capName}" = proto; };
        in
        builtins.foldl' addCap acc provides;
    in
    builtins.foldl' addService { } services;

  capabilityProto =
    capIndex: capName:
    if builtins.hasAttr capName capIndex then
      capIndex.${capName}
    else
      throwError {
        code = "E_POLICY_UNKNOWN_CAPABILITY";
        site = null;
        path = [
          "policy"
          "catalog"
          "services"
        ];
        message = "referenced capability '${capName}' not provided by any service";
        hints = [
          "Add a service that provides '${capName}'."
          "Or change the rule to reference an existing capability."
        ];
      };

  mkRuleSource =
    idx: rule:
    let
      rid = if rule ? id then rule.id else "rule-${toString idx}";
      prio = if rule ? priority then rule.priority else 0;
    in
    {
      kind = "rule";
      index = idx;
      id = rid;
      priority = prio;
    };

  normalizeRuleWithProvenance =
    tenants: capIndex: idx: rule:
    let
      from0 = rule.from or { };
      to0 = rule.to or { };

      _fromShape = ensure ((from0 ? kind) && from0.kind == "tenant" && (from0 ? name)) {
        code = "E_POLICY_RULE_FROM_SHAPE";
        site = null;
        path = [
          "policy"
          "rules"
          idx
          "from"
        ];
        message = "rule.from must be { kind=\"tenant\"; name=...; }";
        hints = [ "Set rule.from.kind = \"tenant\" and rule.from.name = \"...\"." ];
      };

      _fromExists = ensure (builtins.elem from0.name tenants) {
        code = "E_POLICY_UNKNOWN_TENANT";
        site = null;
        path = [
          "policy"
          "rules"
          idx
          "from"
          "name"
        ];
        message = "rule references unknown tenant '${from0.name}'";
        hints = [ "Declare tenant '${from0.name}' under ownership.prefixes." ];
      };

      from = {
        subject = from0.name;
      };

      to =
        if to0 ? external then
          { external = to0.external; }
        else if (to0 ? kind) && to0.kind == "tenant" && (to0 ? name) then
          let
            _toExists = ensure (builtins.elem to0.name tenants) {
              code = "E_POLICY_UNKNOWN_TENANT";
              site = null;
              path = [
                "policy"
                "rules"
                idx
                "to"
                "name"
              ];
              message = "rule references unknown tenant '${to0.name}'";
              hints = [ "Declare tenant '${to0.name}' under ownership.prefixes." ];
            };
          in
          (
            {
              subject = to0.name;
            }
            // (
              if to0 ? capability then
                let
                  _capExists = ensure (builtins.hasAttr to0.capability capIndex) {
                    code = "E_POLICY_UNKNOWN_CAPABILITY";
                    site = null;
                    path = [
                      "policy"
                      "rules"
                      idx
                      "to"
                      "capability"
                    ];
                    message = "rule references unknown capability '${to0.capability}'";
                    hints = [ "Add a service providing '${to0.capability}'." ];
                  };
                in
                {
                  capability = to0.capability;
                }
              else
                { }
            )
          )
        else
          throwError {
            code = "E_POLICY_RULE_TO_SHAPE";
            site = null;
            path = [
              "policy"
              "rules"
              idx
              "to"
            ];
            message = "invalid rule.to";
            hints = [
              "Use { external = \"default\"; } for external targets."
              "Or use { kind = \"tenant\"; name = \"...\"; } for tenant targets."
            ];
          };

      proto =
        if rule ? proto then
          rule.proto
        else if to0 ? capability then
          capabilityProto capIndex to0.capability
        else
          [ "any" ];
    in
    {
      source = mkRuleSource idx rule;
      from = from;
      to = to;
      action = rule.action or "deny";
      proto = proto;
    };

  sortRules =
    rules:
    let
      cmp =
        a: b:
        if a.source.priority < b.source.priority then
          true
        else if a.source.priority > b.source.priority then
          false
        else
          a.source.index < b.source.index;
    in
    lib.sort cmp rules;

  normalizeNatIngress =
    policy:
    let
      catalog = policy.catalog or { };
      services = catalog.services or [ ];
      serviceNames = map (s: s.name) services;

      isExternallyExposed =
        s:
        let
          exposure = s.exposure or { };
        in
        (exposure.external or false) == true;

      exposedServices = map (s: s.name) (lib.filter isExternallyExposed services);

      nat0 = policy.nat or { };
      ingress0 = nat0.ingress or [ ];

      expandOne =
        n:
        let
          svcRef = n.toService or null;

          _shape = ensure (svcRef != null && svcRef ? name) {
            code = "E_NAT_INGRESS_SHAPE";
            site = null;
            path = [
              "policy"
              "nat"
              "ingress"
            ];
            message = "nat.ingress entry must reference toService.name";
            hints = [ "Set nat.ingress[].toService.name = \"...\"." ];
          };

          svcName = svcRef.name;

          _exists = ensure (builtins.elem svcName serviceNames) {
            code = "E_POLICY_UNKNOWN_SERVICE";
            site = null;
            path = [
              "policy"
              "nat"
              "ingress"
            ];
            message = "nat.ingress references unknown service '${svcName}'";
            hints = [ "Declare service '${svcName}' under policy.catalog.services." ];
          };
        in
        {
          fromExternal = n.fromExternal or "default";
          toService = {
            kind = "service";
            name = svcName;
          };
        };

      expanded = map expandOne ingress0;

      _uniqNat = assertUnique "nat ingress service" (map (e: e.toService.name) expanded);

      ingressNames = map (e: e.toService.name) expanded;

      _exposedHaveNat = map (
        svcName:
        ensure (builtins.elem svcName ingressNames) {
          code = "E_NAT_EXPOSED_MISSING_INGRESS";
          site = null;
          path = [
            "policy"
            "nat"
            "ingress"
          ];
          message = "externally exposed service '${svcName}' must have matching policy.nat.ingress entry";
          hints = [
            "Add a nat.ingress entry mapping fromExternal to ${svcName}."
            "Or remove exposure.external = true from the service."
          ];
        }
      ) exposedServices;

      _forced = builtins.deepSeq {
        inherit
          _uniqNat
          _exposedHaveNat
          ;
      } true;
    in
    if _forced then expanded else expanded;
in
{
  inherit
    matchListToProto
    buildCapabilityIndex
    capabilityProto
    mkRuleSource
    normalizeRuleWithProvenance
    sortRules
    normalizeNatIngress
    ;
}
