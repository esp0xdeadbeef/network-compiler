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

  mkPolicyUpstream4ForLink =
    lname: class:
    let
      nh4 = coreEpAddrForLink4 lname;
      overlayLink = if lib.hasPrefix "overlay:" class then pickLinkForOverlay class else null;
      onOverlayLink = overlayLink != null && lname == overlayLink;
    in
    if defaultRouteMode == "blackhole" then
      [ ]
    else if nh4 == null then
      [ ]
    else if defaultRouteMode == "computed" then
      if class == "internet" && upstreamAllowed "internet" then
        map (p: {
          dst = p;
          via4 = nh4;
        }) (topo._internet.internet4 or [ ])
      else if lib.hasPrefix "overlay:" class && upstreamAllowed class && onOverlayLink then
        map (p: {
          dst = p;
          via4 = nh4;
        }) (topo._internet.internet4 or [ ])
      else
        [ ]
    else if class == "default" && upstreamAllowed "default" then
      [
        {
          dst = "0.0.0.0/0";
          via4 = nh4;
        }
      ]
    else if class == "internet" && upstreamAllowed "internet" then
      [
        {
          dst = "0.0.0.0/0";
          via4 = nh4;
        }
      ]
    else if lib.hasPrefix "overlay:" class && upstreamAllowed class && onOverlayLink then
      [
        {
          dst = "0.0.0.0/0";
          via4 = nh4;
        }
      ]
    else
      [ ];

  mkPolicyUpstream6ForLink =
    lname: class:
    let
      nh6 = coreEpAddrForLink6 lname;
      overlayLink = if lib.hasPrefix "overlay:" class then pickLinkForOverlay class else null;
      onOverlayLink = overlayLink != null && lname == overlayLink;
    in
    if defaultRouteMode == "blackhole" then
      [ ]
    else if nh6 == null then
      [ ]
    else if defaultRouteMode == "computed" then
      if class == "internet" && upstreamAllowed "internet" then
        map (p: {
          dst = p;
          via6 = nh6;
        }) (topo._internet.internet6 or [ ])
      else if lib.hasPrefix "overlay:" class && upstreamAllowed class && onOverlayLink then
        map (p: {
          dst = p;
          via6 = nh6;
        }) (topo._internet.internet6 or [ ])
      else
        [ ]
    else if class == "default" && upstreamAllowed "default" then
      [
        {
          dst = "::/0";
          via6 = nh6;
        }
      ]
    else if class == "internet" && upstreamAllowed "internet" then
      [
        {
          dst = "::/0";
          via6 = nh6;
        }
      ]
    else if lib.hasPrefix "overlay:" class && upstreamAllowed class && onOverlayLink then
      [
        {
          dst = "::/0";
          via6 = nh6;
        }
      ]
    else
      [ ];

  mkPolicyRoutes4ForLink =
    lname:
    lib.flatten (
      (mkPolicyUpstream4ForLink lname "default")
      ++ (mkPolicyUpstream4ForLink lname "internet")
      ++ (lib.concatMap (c: mkPolicyUpstream4ForLink lname c) overlayClassesWanted)
    );

  mkPolicyRoutes6ForLink =
    lname:
    lib.flatten (
      (mkPolicyUpstream6ForLink lname "default")
      ++ (mkPolicyUpstream6ForLink lname "internet")
      ++ (lib.concatMap (c: mkPolicyUpstream6ForLink lname c) overlayClassesWanted)
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

      policyRoutes4 = mkPolicyRoutes4ForLink lname;
      policyRoutes6 = mkPolicyRoutes6ForLink lname;

      endpoints1 = (l.endpoints or { }) // {
        "${core}" = coreEp0 // {

          routes4 = mkCoreRoutes4 p4;
          routes6 = mkCoreRoutes6 p6;
        };

        "${policyNodeName}" = policyEp0 // {

          routes4 = policyRoutes4;
          routes6 = policyRoutes6;
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
