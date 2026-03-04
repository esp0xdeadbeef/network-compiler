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

  normalizeExternalRef =
    siteKey: idx: externals: ext:
    let
      _shape = ensure (builtins.isString ext && ext != "") {
        code = "E_POLICY_EXTERNAL_SHAPE";
        site = siteKey;
        path = [
          "policy"
          "rules"
          idx
          "to"
          "external"
        ];
        message = "rule.to.external must be a non-empty string";
        hints = [ "Set rule.to.external = \"<uplink-or-overlay-name>\"." ];
      };

      _noDefault = ensure (ext != "default") {
        code = "E_POLICY_EXTERNAL_DEFAULT_FORBIDDEN";
        site = siteKey;
        path = [
          "policy"
          "rules"
          idx
          "to"
          "external"
        ];
        message = "the keyword \"default\" must not be used for external routing";
        hints = [
          "Replace external = \"default\" with an explicit uplink name (e.g. \"wan\")."
          "For overlays, reference the explicit overlay name."
        ];
      };

      _exists = ensure (builtins.elem ext externals) {
        code = "E_POLICY_UNKNOWN_EXTERNAL";
        site = siteKey;
        path = [
          "policy"
          "rules"
          idx
          "to"
          "external"
        ];
        message = "rule references unknown external '${ext}'";
        hints = [
          "Declare an uplink under topology.nodes.<core>.uplinks.<name>."
          "Or declare a transport overlay with transport.overlays[].name."
        ];
      };
    in
    ext;

  normalizeRuleWithProvenance =
    siteKey: externals: tenants: capIndex: idx: rule:
    let
      from0 = rule.from or { };
      to0 = rule.to or { };

      _fromShape = ensure ((from0 ? kind) && from0.kind == "tenant" && (from0 ? name)) {
        code = "E_POLICY_RULE_FROM_SHAPE";
        site = siteKey;
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
        site = siteKey;
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
          {
            external = normalizeExternalRef siteKey idx externals to0.external;
          }
        else if (to0 ? kind) && to0.kind == "tenant" && (to0 ? name) then
          let
            _toExists = ensure (builtins.elem to0.name tenants) {
              code = "E_POLICY_UNKNOWN_TENANT";
              site = siteKey;
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
                    site = siteKey;
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
            site = siteKey;
            path = [
              "policy"
              "rules"
              idx
              "to"
            ];
            message = "invalid rule.to";
            hints = [
              "Use { external = \"<uplink-or-overlay-name>\"; } for external targets."
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
    siteKey: uplinks: policy:
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

      normalizeFromExternal =
        idx: n:
        let
          ext = n.fromExternal or null;

          _present = ensure (ext != null) {
            code = "E_NAT_INGRESS_MISSING_FROM_EXTERNAL";
            site = siteKey;
            path = [
              "policy"
              "nat"
              "ingress"
              idx
              "fromExternal"
            ];
            message = "nat.ingress[].fromExternal is required (no implicit default uplink)";
            hints = [ "Set fromExternal to an explicit uplink name (e.g. \"wan\")." ];
          };

          _shape = ensure (builtins.isString ext && ext != "") {
            code = "E_NAT_INGRESS_FROM_EXTERNAL_SHAPE";
            site = siteKey;
            path = [
              "policy"
              "nat"
              "ingress"
              idx
              "fromExternal"
            ];
            message = "nat.ingress[].fromExternal must be a non-empty string";
            hints = [ "Set fromExternal = \"<uplink-name>\"." ];
          };

          _noDefault = ensure (ext != "default") {
            code = "E_NAT_INGRESS_DEFAULT_FORBIDDEN";
            site = siteKey;
            path = [
              "policy"
              "nat"
              "ingress"
              idx
              "fromExternal"
            ];
            message = "the keyword \"default\" must not be used for external routing";
            hints = [ "Replace fromExternal = \"default\" with an explicit uplink name (e.g. \"wan\")." ];
          };

          _exists = ensure (builtins.elem ext uplinks) {
            code = "E_NAT_INGRESS_UNKNOWN_UPLINK";
            site = siteKey;
            path = [
              "policy"
              "nat"
              "ingress"
              idx
              "fromExternal"
            ];
            message = "nat.ingress references unknown uplink '${ext}'";
            hints = [ "Declare topology.nodes.<core>.uplinks.${ext} with ipv4/ipv6 prefixes." ];
          };
        in
        ext;

      expandOne =
        idx: n:
        let
          svcRef = n.toService or null;

          _shape = ensure (svcRef != null && svcRef ? name) {
            code = "E_NAT_INGRESS_SHAPE";
            site = siteKey;
            path = [
              "policy"
              "nat"
              "ingress"
              idx
            ];
            message = "nat.ingress entry must reference toService.name";
            hints = [ "Set nat.ingress[].toService.name = \"...\"." ];
          };

          svcName = svcRef.name;

          _exists = ensure (builtins.elem svcName serviceNames) {
            code = "E_POLICY_UNKNOWN_SERVICE";
            site = siteKey;
            path = [
              "policy"
              "nat"
              "ingress"
              idx
              "toService"
              "name"
            ];
            message = "nat.ingress references unknown service '${svcName}'";
            hints = [ "Declare service '${svcName}' under policy.catalog.services." ];
          };

          fromExternal = normalizeFromExternal idx n;
        in
        {
          inherit fromExternal;
          toService = {
            kind = "service";
            name = svcName;
          };
        };

      expanded = lib.imap0 expandOne ingress0;

      _uniqNat = assertUnique "nat ingress service" (map (e: e.toService.name) expanded);

      ingressNames = map (e: e.toService.name) expanded;

      _exposedHaveNat = map (
        svcName:
        ensure (builtins.elem svcName ingressNames) {
          code = "E_NAT_EXPOSED_MISSING_INGRESS";
          site = siteKey;
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
