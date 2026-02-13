# ./tests/routing-semantics-positive.nix
{ lib }:

let
  inputs = import ../dev/debug-lib/inputs.nix { sopsData = { }; };
  mode = if inputs ? defaultRouteMode then inputs.defaultRouteMode else "default";

  routed = import ../dev/debug-lib/30-routing.nix { sopsData = { }; };

  links = if routed ? links then routed.links else { };

  policyNode = "s-router-policy-only";
  coreNode = "s-router-core-wan";
  accessNode = "s-router-access-10";

  getLink =
    name: if links ? ${name} then links.${name} else throw "routing-semantics: missing link '${name}'";

  getEp =
    l: n:
    let
      eps = if l ? endpoints then l.endpoints else { };
    in
    if eps ? ${n} then eps.${n} else { };

  hasRoute =
    pred: rs:
    let
      routes = if rs == null then [ ] else rs;
    in
    lib.any pred routes;

  # --------------------------
  # 1) policy-core exists
  # --------------------------
  policyCore = getLink "policy-core";

  # --------------------------
  # 2) core learns tenant routes via policy-core
  # --------------------------
  coreEp = getEp policyCore coreNode;

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

  _assertCoreTenants = lib.assertMsg (coreHasTenant4 && coreHasTenant6) ''
    routing-semantics: core is missing tenant routes on policy-core.

    Expected at least one:
      - 10.10.<vid>.0/24
      - fd42:dead:beef:<vid>::/64
  '';

  # --------------------------
  # 3) policy receives upstream internet via policy-core (mode-aware)
  # --------------------------
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

  # --------------------------
  # 4) access receives internet via policy-access-10 (mode-aware)
  # --------------------------
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

  # --------------------------
  # 5) WAN injects defaults when mode=default (debug semantics)
  # --------------------------
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
builtins.seq _assertCoreTenants (
  builtins.seq _assertPolicyInternet (
    builtins.seq _assertAccessInternet (builtins.seq _assertWanDefault "ROUTING SEMANTICS OK")
  )
)
