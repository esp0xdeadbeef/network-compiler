{
  lib,
  ulaPrefix,
  tenantV4Base,
  policyNodeName ? "s-router-policy-only",
  coreNodeName ? "s-router-core-wan",
}:

topo:

let
  links = topo.links or { };

  policyNode = policyNodeName;
  coreNode = coreNodeName;

  mode = topo.defaultRouteMode or "default";

  stripCidr = s: if s == null then null else builtins.elemAt (lib.splitString "/" s) 0;

  tenant4Dst = vid: "${tenantV4Base}.${toString vid}.0/24";
  tenant6DstUla = vid: "${ulaPrefix}:${toString vid}::/64";

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

  tenantVids = lib.unique (
    lib.filter (x: x != null) (
      lib.concatMap (
        l:
        if l.kind == "p2p" && lib.hasPrefix "policy-access-" (l.name or "") then
          let
            ms = l.members or [ ];
            accessNode = if lib.head ms == policyNode then builtins.elemAt ms 1 else lib.head ms;
            epA = getEp l accessNode;
          in
          [ (getTenantVid epA) ]
        else
          [ ]
      ) (lib.attrValues links)
    )
  );

  internet =
    topo._internet or {
      internet4 = [ "0.0.0.0/0" ];
      internet6 = [ "::/0" ];
    };

  policyDefaults4 =
    if mode == "blackhole" then
      [ ]
    else if mode == "computed" then
      map (p: { dst = p; }) internet.internet4
    else
      [ { dst = "0.0.0.0/0"; } ];

  policyDefaults6 =
    if mode == "blackhole" then
      [ ]
    else if mode == "computed" then
      map (p: { dst = p; }) internet.internet6
    else
      [ { dst = "::/0"; } ];

in
topo
// {
  links = lib.mapAttrs (
    _: l:
    if
      l.kind == "p2p"
      && (l.name or "") == "policy-core"
      && lib.elem policyNode (l.members or [ ])
      && lib.elem coreNode (l.members or [ ])
    then
      let
        epPolicy = getEp l policyNode;
        epCore = getEp l coreNode;

        via4toPolicy = stripCidr epPolicy.addr4;
        via6toPolicy = stripCidr epPolicy.addr6;

        coreRoutes4 = map (vid: {
          dst = tenant4Dst vid;
          via4 = via4toPolicy;
        }) tenantVids;
        coreRoutes6 = map (vid: {
          dst = tenant6DstUla vid;
          via6 = via6toPolicy;
        }) tenantVids;

        policyUp4 = map (r: r // { via4 = stripCidr epCore.addr4; }) policyDefaults4;
        policyUp6 = map (r: r // { via6 = stripCidr epCore.addr6; }) policyDefaults6;
      in
      setEp
        (setEp l policyNode (
          epPolicy
          // {
            routes4 = policyUp4;
            routes6 = policyUp6;
          }
        ))
        coreNode
        (
          epCore
          // {
            routes4 = coreRoutes4;
            routes6 = coreRoutes6;
          }
        )
    else
      l
  ) links;
}
