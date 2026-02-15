{
  lib,
  ulaPrefix,
  tenantV4Base,

  policyNodeName,
}:

topo:

let
  links = topo.links or { };
  policyNode = policyNodeName;

  defaultMode = topo.defaultRouteMode or "default";

  rc = import ./route-classes.nix { inherit lib; };

  intent0 = topo.policyIntent or { };

  _intentClassesOk = rc.assertClasses "policyIntent.advertiseClasses" (
    intent0.advertiseClasses or [ ]
  );

  advertiseClasses = rc.normalize (intent0.advertiseClasses or [ ]);
  advertises = c: lib.elem c advertiseClasses;

  exitTenants0 = intent0.exitTenants or [ ];
  exitTenants = if exitTenants0 == null then [ ] else exitTenants0;
  tenantMayExit = vid: vid != null && lib.elem vid exitTenants;

  isPolicyAccess =
    lname: l:
    l.kind == "p2p" && lib.hasPrefix "policy-access-" lname && lib.elem policyNode (l.members or [ ]);

  stripCidr = s: if s == null then null else builtins.elemAt (lib.splitString "/" s) 0;

  tenant4Dst = vid: "${tenantV4Base}.${toString vid}.0/24";
  tenant6DstUla = vid: "${ulaPrefix}:${toString vid}::/64";

  ula48 = "${ulaPrefix}::/48";

  getEp = l: n: (l.endpoints or { }).${n} or { };

  setEp =
    l: n: ep:
    l
    // {
      endpoints = (l.endpoints or { }) // {
        "${n}" = ep;
      };
    };

  getTenantVid =
    ep:
    if ep ? tenant && builtins.isAttrs ep.tenant && ep.tenant ? vlanId then ep.tenant.vlanId else null;

  computed4 =
    if topo ? _internet && topo._internet ? internet4 then
      map (p: { dst = p; }) topo._internet.internet4
    else
      [ ];

  computed6 =
    if topo ? _internet && topo._internet ? internet6 then
      map (p: { dst = p; }) topo._internet.internet6
    else
      [ ];

  mkAccessAdv4 =
    { gw4, allowExit }:
    if !allowExit then
      [ ]
    else if defaultMode == "blackhole" then
      [ ]
    else if defaultMode == "computed" then
      if advertises "internet" then map (r: r // { via4 = gw4; }) computed4 else [ ]
    else if advertises "default" then
      [
        {
          dst = "0.0.0.0/0";
          via4 = gw4;
        }
      ]
    else
      [ ];

  mkAccessAdv6 =
    { gw6, allowExit }:
    if !allowExit then
      [ ]
    else if defaultMode == "blackhole" then
      [ ]
    else if defaultMode == "computed" then
      if advertises "internet" then map (r: r // { via6 = gw6; }) computed6 else [ ]
    else if advertises "default" then
      [
        {
          dst = "::/0";
          via6 = gw6;
        }
      ]
    else
      [ ];

in
builtins.seq _intentClassesOk (
  topo
  // {
    links = lib.mapAttrs (
      lname: l:
      if !(isPolicyAccess lname l) then
        l
      else
        let
          ms = l.members or [ ];

          accessNode = if lib.head ms == policyNode then builtins.elemAt ms 1 else lib.head ms;

          epAccess = getEp l accessNode;
          epPolicy = getEp l policyNode;

          vid = getTenantVid epAccess;

          gw4 = stripCidr epPolicy.addr4;
          gw6 = stripCidr epPolicy.addr6;

          via4toAccess = stripCidr epAccess.addr4;
          via6toAccess = stripCidr epAccess.addr6;

          allowExit = tenantMayExit vid;

          accessRoutes4 = mkAccessAdv4 { inherit gw4 allowExit; };

          accessRoutes6 = [
            {
              dst = ula48;
              via6 = gw6;
            }
          ]
          ++ (mkAccessAdv6 { inherit gw6 allowExit; });

          policyRoutes4 = lib.optional (vid != null) {
            dst = tenant4Dst vid;
            via4 = via4toAccess;
          };

          policyRoutes6 = lib.optional (vid != null) {
            dst = tenant6DstUla vid;
            via6 = via6toAccess;
          };
        in
        setEp
          (setEp l accessNode (
            epAccess
            // {
              routes4 = (epAccess.routes4 or [ ]) ++ accessRoutes4;
              routes6 = (epAccess.routes6 or [ ]) ++ accessRoutes6;
            }
          ))
          policyNode
          (
            epPolicy
            // {
              routes4 = (epPolicy.routes4 or [ ]) ++ policyRoutes4;
              routes6 = (epPolicy.routes6 or [ ]) ++ policyRoutes6;
            }
          )
    ) links;
  }
)
