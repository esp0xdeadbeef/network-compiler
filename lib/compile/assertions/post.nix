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

  policyCoreLink =
    let
      candidates = lib.filterAttrs (
        _: l:
        l.kind == "p2p"
        && (l.name or "") == "policy-core"
        && lib.elem policyNodeName (l.members or [ ])
        && lib.elem coreNodeName (l.members or [ ])
      ) links;
    in
    if candidates == { } then null else lib.head (lib.attrValues candidates);

  coreHasTenantRoutes =
    if policyCoreLink == null then
      false
    else
      let
        epCore = getEp policyCoreLink coreNodeName;
        r4 = epCore.routes4 or [ ];
        r6 = epCore.routes6 or [ ];
      in
      (r4 != [ ]) || (r6 != [ ]);

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

      ok =
        if mode == "default" then
          hasDefault4 && hasDefault6
        else if mode == "computed" then
          (r4 != [ ]) && (r6 != [ ])
        else

          (r4 == [ ]) && (!hasDefault6);
    in
    ok
  ) (lib.attrValues policyAccessLinks);

in
{
  assertions = [
    {
      assertion = policyCoreLink != null;
      message = "Missing required p2p link 'policy-core' between '${policyNodeName}' and '${coreNodeName}'.";
    }
    {
      assertion = coreHasTenantRoutes;
      message = "Core has no routes on policy-core endpoint. This usually means policy-core routing stopped writing link endpoint routes.";
    }
    {
      assertion = accessHasExpectedDefaults;
      message = "Access nodes do not have expected default/computed/blackhole routing on policy-access links for defaultRouteMode='${mode}'.";
    }
  ];
}
