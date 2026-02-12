# ./lib/compile/routing/policy-core.nix
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

  internet = topo._internet or null;

  computedDefaults4 =
    if internet != null && internet ? internet4 then
      lib.filter (r: r.dst != "0.0.0.0/0") (map (p: { dst = p; }) internet.internet4)
    else
      [ ];

  computedDefaults6 =
    if internet != null && internet ? internet6 then
      lib.filter (r: r.dst != "::/0") (map (p: { dst = p; }) internet.internet6)
    else
      [ ];

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

        policyDefaults4 = map (r: r // { via4 = stripCidr epCore.addr4; }) computedDefaults4;

        policyDefaults6 = map (r: r // { via6 = stripCidr epCore.addr6; }) computedDefaults6;

      in
      setEp
        (setEp l policyNode (
          epPolicy
          // {
            routes4 = policyDefaults4;
            routes6 = policyDefaults6;
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
