{
  lib,
  policyNodeName,
  coreNodeName,
}:

topo:

let
  mode = topo.defaultRouteMode or "default";
  links = topo.links or { };

  getEp = l: n: (l.endpoints or { }).${n} or { };

  isPolicyAccess =
    lname: l:
    l.kind == "p2p"
    && lib.hasPrefix "policy-access-" lname
    && lib.elem policyNodeName (l.members or [ ]);

  policyAccessLinks = lib.filterAttrs isPolicyAccess links;

  isPolicyCore =
    lname: l:
    l.kind == "p2p"
    && (
      lname == "policy-core"
      || lib.hasPrefix "policy-core-" lname
      || (l.name or "") == "policy-core"
      || lib.hasPrefix "policy-core-" (l.name or "")
    )
    && lib.elem policyNodeName (l.members or [ ])
    && lib.any (m: m == coreNodeName || lib.hasPrefix "${coreNodeName}-" m) (l.members or [ ]);

  policyCoreLinks = lib.filterAttrs isPolicyCore links;

  _assertHavePolicyCore = {
    assertion = policyCoreLinks != { };
    message = "Missing required p2p link(s) 'policy-core-*' between '${policyNodeName}' and '${coreNodeName}-<ctx>' (or legacy 'policy-core').";
  };

  coreHasTenantRoutes =
    let
      isTenant4 = r: lib.hasInfix "." (r.dst or "") && lib.hasSuffix "/24" (r.dst or "");
      isTenant6 = r: lib.hasInfix ":" (r.dst or "") && lib.hasSuffix "/64" (r.dst or "");

      coreEpHasTenants =
        lname: l:
        let
          ms = l.members or [ ];
          coreMember =
            if lib.length ms != 2 then
              null
            else if lib.head ms == policyNodeName then
              builtins.elemAt ms 1
            else
              lib.head ms;

          epCore = if coreMember == null then { } else getEp l coreMember;

          r4 = epCore.routes4 or [ ];
          r6 = epCore.routes6 or [ ];
        in
        (lib.any isTenant4 r4) || (lib.any isTenant6 r6);
    in
    lib.any (x: x) (lib.mapAttrsToList coreEpHasTenants policyCoreLinks);

  coreHasRouteToPolicy =
    let
      coreEpHasAnyRoute =
        lname: l:
        let
          ms = l.members or [ ];
          coreMember =
            if lib.length ms != 2 then
              null
            else if lib.head ms == policyNodeName then
              builtins.elemAt ms 1
            else
              lib.head ms;

          epCore = if coreMember == null then { } else getEp l coreMember;

          r4 = epCore.routes4 or [ ];
          r6 = epCore.routes6 or [ ];
        in
        (r4 != [ ]) || (r6 != [ ]);
    in
    lib.any (x: x) (lib.mapAttrsToList coreEpHasAnyRoute policyCoreLinks);

  accessHasExpectedDefaults = lib.all (
    l:
    let
      ms = l.members or [ ];
      accessNode = if lib.head ms == policyNodeName then builtins.elemAt ms 1 else lib.head ms;
      epA = getEp l accessNode;

      r4 = epA.routes4 or [ ];
      r6 = epA.routes6 or [ ];

      has0 = pred: xs: lib.any pred xs;

      hasDefault4 = has0 (r: (r.dst or "") == "0.0.0.0/0") r4;
      hasDefault6 = has0 (r: (r.dst or "") == "::/0") r6;

      hasUla48 = has0 (r: (r.dst or "") == "${topo.ulaPrefix}::/48") r6;

      ok =
        if mode == "default" then
          hasUla48 && (hasDefault4 || r4 == [ ]) && (hasDefault6 || r6 != [ ])
        else if mode == "computed" then
          hasUla48 && (r4 != [ ]) && (r6 != [ ])
        else
          hasUla48 && (r4 == [ ]) && (!hasDefault6);
    in
    ok
  ) (lib.attrValues policyAccessLinks);

in
{
  assertions = [
    _assertHavePolicyCore
    {
      assertion = !coreHasTenantRoutes;
      message = "Invariant violation: core has tenant routes on policy-core. Core must NEVER contain tenant prefixes.";
    }
    {
      assertion = coreHasRouteToPolicy;
      message = "Core has no route-to-policy on policy-core endpoint(s). Core must include route-to-policy (host route) on policy-core.";
    }
    {
      assertion = accessHasExpectedDefaults;
      message = "Access nodes do not have expected routing on policy-access links for defaultRouteMode='${mode}' (and explicit policy intent).";
    }
  ];
}
