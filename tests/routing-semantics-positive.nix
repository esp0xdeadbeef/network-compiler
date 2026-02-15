{ lib }:

let
  evalNetwork = import ../lib/eval.nix { inherit lib; };

  inputs0 = import ../examples/single-site { sopsData = { }; };

  inputs = inputs0 // {

    policyIntent =
      inputs0.policyIntent or {
        exitTenants = inputs0.tenantVlans or [ 10 ];
        upstreamClasses = [
          "default"
          "internet"
        ];
        advertiseClasses = [
          "default"
          "internet"
        ];
      };
  };

  mode = if inputs ? defaultRouteMode then inputs.defaultRouteMode else "default";

  routed = evalNetwork inputs;

  links = if routed ? links then routed.links else { };

  policyNode =
    if inputs ? policyNodeName then
      inputs.policyNodeName
    else if routed ? policyNodeName then
      routed.policyNodeName
    else
      throw "routing-semantics: missing policyNodeName in inputs/routed";

  coreHost =
    if inputs ? coreNodeName then
      inputs.coreNodeName
    else if routed ? coreNodeName then
      routed.coreNodeName
    else
      throw "routing-semantics: missing coreNodeName in inputs/routed";

  accessPrefix =
    if inputs ? accessNodePrefix then
      inputs.accessNodePrefix
    else if routed ? accessNodePrefix then
      routed.accessNodePrefix
    else
      throw "routing-semantics: missing accessNodePrefix in inputs/routed";

  accessNode = "${accessPrefix}-10";

  getLink =
    name:
    if links ? "${name}" then links.${name} else throw "routing-semantics: missing link '${name}'";

  getEp =
    l: n:
    let
      eps = if l ? endpoints then l.endpoints else { };
    in
    if eps ? "${n}" then eps.${n} else { };

  hasRoute =
    pred: rs:
    let
      routes = if rs == null then [ ] else rs;
    in
    lib.any pred routes;

  policyCoreNames = lib.sort (a: b: a < b) (
    lib.filter (n: n == "policy-core" || lib.hasPrefix "policy-core-" n) (builtins.attrNames links)
  );

  policyCoreLinkName =
    if policyCoreNames == [ ] then
      throw "routing-semantics: missing policy-core link(s)"
    else
      lib.head policyCoreNames;

  policyCore = getLink policyCoreLinkName;

  members = policyCore.members or [ ];

  coreMember =
    if lib.length members != 2 then
      throw "routing-semantics: policy-core must be p2p (2 members)"
    else if lib.head members == policyNode then
      builtins.elemAt members 1
    else
      lib.head members;

  coreEp = getEp policyCore coreMember;

  coreRoutes4 = if coreEp ? routes4 then coreEp.routes4 else [ ];
  coreRoutes6 = if coreEp ? routes6 then coreEp.routes6 else [ ];

  coreHasTenant4 = hasRoute (
    r:
    lib.hasPrefix "10.10." (if r ? dst then r.dst else "")
    && lib.hasSuffix "/24" (if r ? dst then r.dst else "")
  ) coreRoutes4;

  coreHasTenant6 = hasRoute (
    r:
    lib.hasPrefix "fd42:dead:beef:" (if r ? dst then r.dst else "")
    && lib.hasSuffix "/64" (if r ? dst then r.dst else "")
  ) coreRoutes6;

  _assertCoreNoTenants = lib.assertMsg (!coreHasTenant4 && !coreHasTenant6) ''
    routing-semantics: core must NOT contain tenant routes on policy-core.

    coreHost = "${coreHost}"
    coreMember (selected) = "${coreMember}"

    Observed:
      tenant v4 routes present = ${toString coreHasTenant4}
      tenant v6 routes present = ${toString coreHasTenant6}
  '';

  policyEp = getEp policyCore policyNode;

  policyR4 = if policyEp ? routes4 then policyEp.routes4 else [ ];
  policyR6 = if policyEp ? routes6 then policyEp.routes6 else [ ];

  policyHasAny4 = policyR4 != [ ];
  policyHasAny6 = policyR6 != [ ];

  policyHasDefault4 = hasRoute (r: (if r ? dst then r.dst else "") == "0.0.0.0/0") policyR4;
  policyHasDefault6 = hasRoute (r: (if r ? dst then r.dst else "") == "::/0") policyR6;

  policyOk =
    if mode == "blackhole" then
      (!policyHasAny4) && (!policyHasAny6) && (!policyHasDefault4) && (!policyHasDefault6)
    else if mode == "computed" then
      policyHasAny4 && policyHasAny6
    else
      policyHasDefault4 && policyHasDefault6;

  _assertPolicyInternet = lib.assertMsg policyOk ''
    routing-semantics: policy does not have expected upstream internet routes via policy-core for defaultRouteMode='${mode}'.

    Observed:
      routes4 count = ${toString (lib.length policyR4)}
      routes6 count = ${toString (lib.length policyR6)}
  '';

  policyAccessLinkName = "policy-access-10";
  policyAccess = getLink policyAccessLinkName;

  accessEp = getEp policyAccess accessNode;

  accessR4 = if accessEp ? routes4 then accessEp.routes4 else [ ];
  accessR6 = if accessEp ? routes6 then accessEp.routes6 else [ ];

  accessHasAny4 = accessR4 != [ ];
  accessHasAny6 = accessR6 != [ ];

  accessHasDefault4 = hasRoute (r: (if r ? dst then r.dst else "") == "0.0.0.0/0") accessR4;
  accessHasDefault6 = hasRoute (r: (if r ? dst then r.dst else "") == "::/0") accessR6;

  accessHasUla48 = hasRoute (r: (if r ? dst then r.dst else "") == "fd42:dead:beef::/48") accessR6;

  accessOk =
    if mode == "blackhole" then
      (accessR4 == [ ]) && (!accessHasDefault6) && accessHasUla48
    else if mode == "computed" then
      accessHasAny4 && accessHasAny6 && accessHasUla48
    else
      accessHasDefault4 && accessHasDefault6 && accessHasUla48;

  _assertAccessInternet = lib.assertMsg accessOk ''
    routing-semantics: access does not have expected internet routes via policy-access-10 for defaultRouteMode='${mode}'.

    Observed:
      routes4 count = ${toString (lib.length accessR4)}
      routes6 count = ${toString (lib.length accessR6)}
      has ula48      = ${toString accessHasUla48}
  '';

  wanLinks = lib.filter (l: (if l ? kind then l.kind else null) == "wan") (lib.attrValues links);

  epHasDefault =
    ep:
    let
      r4 = if ep ? routes4 then ep.routes4 else [ ];
      r6 = if ep ? routes6 then ep.routes6 else [ ];
    in
    (hasRoute (r: (if r ? dst then r.dst else null) == "0.0.0.0/0") r4)
    || (hasRoute (r: (if r ? dst then r.dst else null) == "::/0") r6);

  wanHasDefault = lib.any (
    l: lib.any epHasDefault (lib.attrValues (if l ? endpoints then l.endpoints else { }))
  ) wanLinks;

  _assertWanDefault = lib.assertMsg (mode != "default" || wanHasDefault) ''
    routing-semantics: defaultRouteMode='default' expects at least one WAN endpoint to advertise a default route.

    No WAN endpoints include 0.0.0.0/0 or ::/0 in routes4/routes6.
  '';

in
builtins.seq _assertCoreNoTenants (
  builtins.seq _assertPolicyInternet (
    builtins.seq _assertAccessInternet (builtins.seq _assertWanDefault "ROUTING SEMANTICS OK")
  )
)
