{
  lib,
  ulaPrefix,
  tenantV4Base,
  policyNodeName,
  coreNodeName,
}:

topo:

let
  links0 = topo.links or { };

  isPolicyCore =
    lname: l:
    (l.kind or null) == "p2p"
    && (
      lname == "policy-core"
      || lib.hasPrefix "policy-core-" lname
      || (l.name or "") == "policy-core"
      || lib.hasPrefix "policy-core-" (l.name or "")
    )
    && lib.elem policyNodeName (l.members or [ ]);

  policyCoreLinks = lib.filterAttrs isPolicyCore links0;

  _assertHavePolicyCore = lib.assertMsg (policyCoreLinks != { }) ''
    Missing required p2p policy-core link(s) between '${policyNodeName}' and core context node(s).

    Expected at least one link named:
      - policy-core-<ctx>   (preferred)
    or legacy:
      - policy-core
  '';

  stripCidr = s: builtins.elemAt (lib.splitString "/" s) 0;

  defaultRouteMode = topo.defaultRouteMode or "default";

  rc = import ./route-classes.nix { inherit lib; };
  caps = topo._routingMaps.capabilities or (import ./capabilities.nix { inherit lib; } topo);

  intent0 = topo.policyIntent or { };
  _intentClassesOk = builtins.seq (rc.assertClasses "policyIntent.upstreamClasses" (
    intent0.upstreamClasses or [ ]
  )) (rc.assertClasses "policyIntent.advertiseClasses" (intent0.advertiseClasses or [ ]));

  upstreamClasses = rc.normalize (intent0.upstreamClasses or [ ]);
  haveCaps = caps.allCaps or [ ];

  haveClass = c: lib.elem c haveCaps;
  wantClass = c: lib.elem c upstreamClasses;

  upstreamAllowed = c: wantClass c && haveClass c;

  overlayClassesWanted = lib.filter (c: lib.hasPrefix "overlay:" c) upstreamClasses;

  linkOrder = lib.sort (a: b: a < b) (builtins.attrNames policyCoreLinks);

  firstPolicyCoreName = if linkOrder == [ ] then null else lib.head linkOrder;

  ctxForPolicyCoreLink =
    lname:
    if lib.hasPrefix "policy-core-" lname then
      lib.removePrefix "policy-core-" lname
    else if lib.hasPrefix "policy-core-" (policyCoreLinks.${lname}.name or "") then
      lib.removePrefix "policy-core-" (policyCoreLinks.${lname}.name or "")
    else
      null;

  pickLinkForOverlay =
    ov:
    let
      nm = lib.removePrefix "overlay:" ov;
      exact = "policy-core-${nm}";
    in
    if policyCoreLinks ? "${exact}" then exact else firstPolicyCoreName;

  getEp = l: n: (l.endpoints or { }).${n} or { };

  otherMember =
    l:
    let
      ms = l.members or [ ];
      a = if lib.length ms > 0 then lib.head ms else null;
      b = if lib.length ms > 1 then builtins.elemAt ms 1 else null;
    in
    if a == policyNodeName then b else a;

  coreEpAddrForLink4 =
    lname:
    let
      l = policyCoreLinks.${lname};
      core = otherMember l;
      ep = getEp l core;
    in
    if ep ? addr4 && ep.addr4 != null then stripCidr ep.addr4 else null;

  coreEpAddrForLink6 =
    lname:
    let
      l = policyCoreLinks.${lname};
      core = otherMember l;
      ep = getEp l core;
    in
    if ep ? addr6 && ep.addr6 != null then stripCidr ep.addr6 else null;

  policyEpAddrForLink4 =
    lname:
    let
      l = policyCoreLinks.${lname};
      ep = getEp l policyNodeName;
    in
    if ep ? addr4 && ep.addr4 != null then stripCidr ep.addr4 else null;

  policyEpAddrForLink6 =
    lname:
    let
      l = policyCoreLinks.${lname};
      ep = getEp l policyNodeName;
    in
    if ep ? addr6 && ep.addr6 != null then stripCidr ep.addr6 else null;

  defaultLink = firstPolicyCoreName;

  nhDefault4 = if defaultLink == null then null else coreEpAddrForLink4 defaultLink;
  nhDefault6 = if defaultLink == null then null else coreEpAddrForLink6 defaultLink;

  mkPolicyUpstream4 =
    class:
    if defaultRouteMode == "blackhole" then
      [ ]
    else if defaultRouteMode == "computed" then
      if class == "internet" && upstreamAllowed "internet" && nhDefault4 != null then
        (map (p: {
          dst = p;
          via4 = nhDefault4;
        }) (topo._internet.internet4 or [ ]))
      else
        [ ]
    else if class == "default" && upstreamAllowed "default" && nhDefault4 != null then
      [
        {
          dst = "0.0.0.0/0";
          via4 = nhDefault4;
        }
      ]
    else if lib.hasPrefix "overlay:" class && upstreamAllowed class then
      let
        ln = pickLinkForOverlay class;
        nh = if ln == null then null else coreEpAddrForLink4 ln;
      in
      if nh == null then
        [ ]
      else
        [
          {
            dst = "0.0.0.0/0";
            via4 = nh;
          }
        ]
    else
      [ ];

  mkPolicyUpstream6 =
    class:
    if defaultRouteMode == "blackhole" then
      [ ]
    else if defaultRouteMode == "computed" then
      if class == "internet" && upstreamAllowed "internet" && nhDefault6 != null then
        (map (p: {
          dst = p;
          via6 = nhDefault6;
        }) (topo._internet.internet6 or [ ]))
      else
        [ ]
    else if class == "default" && upstreamAllowed "default" && nhDefault6 != null then
      [
        {
          dst = "::/0";
          via6 = nhDefault6;
        }
      ]
    else if lib.hasPrefix "overlay:" class && upstreamAllowed class then
      let
        ln = pickLinkForOverlay class;
        nh = if ln == null then null else coreEpAddrForLink6 ln;
      in
      if nh == null then
        [ ]
      else
        [
          {
            dst = "::/0";
            via6 = nh;
          }
        ]
    else
      [ ];

  policyUpstream4 = lib.flatten (
    (mkPolicyUpstream4 "default")
    ++ (mkPolicyUpstream4 "internet")
    ++ (lib.concatMap mkPolicyUpstream4 overlayClassesWanted)
  );

  policyUpstream6 = lib.flatten (
    (mkPolicyUpstream6 "default")
    ++ (mkPolicyUpstream6 "internet")
    ++ (lib.concatMap mkPolicyUpstream6 overlayClassesWanted)
  );

  mkCoreRoutes4 = policyAddr4: lib.optional (policyAddr4 != null) { dst = "${policyAddr4}/32"; };
  mkCoreRoutes6 = policyAddr6: lib.optional (policyAddr6 != null) { dst = "${policyAddr6}/128"; };

  rewriteOne =
    lname: l:
    let
      core = otherMember l;

      p4 = policyEpAddrForLink4 lname;
      p6 = policyEpAddrForLink6 lname;

      coreEp0 = getEp l core;
      policyEp0 = getEp l policyNodeName;

      endpoints1 = (l.endpoints or { }) // {
        "${core}" = coreEp0 // {
          routes4 = mkCoreRoutes4 p4;
          routes6 = mkCoreRoutes6 p6;
        };

        "${policyNodeName}" = policyEp0 // {
          routes4 = policyUpstream4;
          routes6 = policyUpstream6;
        };
      };
    in
    l // { endpoints = endpoints1; };

  links1 = lib.mapAttrs rewriteOne policyCoreLinks;

in
builtins.seq _assertHavePolicyCore (
  builtins.seq _intentClassesOk (
    topo
    // {
      links = links0 // links1;
    }
  )
)
