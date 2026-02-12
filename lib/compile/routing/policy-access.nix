# FILE: ./lib/compile/routing/policy-access.nix
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

  isPolicyAccess =
    lname: l:
    l.kind == "p2p" && lib.hasPrefix "policy-access-" lname && lib.elem policyNode (l.members or [ ]);

  stripCidr = s: if s == null then null else builtins.elemAt (lib.splitString "/" s) 0;

  tenant4Dst = vid: "${tenantV4Base}.${toString vid}.0/24";
  tenant6DstUla = vid: "${ulaPrefix}:${toString vid}::/64";

  # Aggregate ULA space (assumes ulaPrefix is /48 base like fd42:dead:beef)
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

        # Access router:
        #  - default IPv4 via policy
        accessRoutes4 = [
          {
            dst = "0.0.0.0/0";
            via4 = gw4;
          }
        ];

        # Access router:
        #  - route ALL internal ULAs to policy
        #  - default IPv6 to policy
        accessRoutes6 = [
          {
            dst = ula48;
            via6 = gw6;
          }
          {
            dst = "::/0";
            via6 = gw6;
          }
        ];

        # Policy router gets explicit per-tenant return routes
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
