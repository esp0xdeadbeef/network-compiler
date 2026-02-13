{
  lib,
  ulaPrefix,
  tenantV4Base,
  policyNodeName ? "s-router-policy-only",
}:

topo:

let
  links = topo.links or { };
  policyNode = policyNodeName;

  defaultMode = if topo ? defaultRouteMode then topo.defaultRouteMode else "default";

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

in
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

        accessDefaults4 =
          if defaultMode == "blackhole" then
            [ ]
          else if defaultMode == "computed" then
            map (r: r // { via4 = gw4; }) computed4
          else
            [
              {
                dst = "0.0.0.0/0";
                via4 = gw4;
              }
            ];

        accessDefaults6 =
          if defaultMode == "blackhole" then
            [ ]
          else if defaultMode == "computed" then
            map (r: r // { via6 = gw6; }) computed6
          else
            [
              {
                dst = "::/0";
                via6 = gw6;
              }
            ];

        accessRoutes4 = accessDefaults4;

        accessRoutes6 = [
          {
            dst = ula48;
            via6 = gw6;
          }
        ]
        ++ accessDefaults6;

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
