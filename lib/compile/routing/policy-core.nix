{
  lib,
  ulaPrefix,
  tenantV4Base,
  policyNodeName,
  coreNodeName,
}:

topo:

let
  links = topo.links or { };

  policyCore =
    if links ? "policy-core" then links."policy-core" else throw "policy-core link is required";

  endpoints0 = policyCore.endpoints or { };

  coreEp = if endpoints0 ? "${coreNodeName}" then endpoints0.${coreNodeName} else { };

  policyEp = if endpoints0 ? "${policyNodeName}" then endpoints0.${policyNodeName} else { };

  stripCidr = s: builtins.elemAt (lib.splitString "/" s) 0;

  coreVia4 = if coreEp ? addr4 && coreEp.addr4 != null then stripCidr coreEp.addr4 else null;

  coreVia6 = if coreEp ? addr6 && coreEp.addr6 != null then stripCidr coreEp.addr6 else null;

  defaultRouteMode = topo.defaultRouteMode or "default";

  tenantVids = lib.unique (
    lib.concatMap (
      lname:
      let
        l = links.${lname};
      in
      lib.concatMap (
        ep:
        if builtins.isAttrs ep && ep ? tenant && builtins.isAttrs ep.tenant && ep.tenant ? vlanId then
          [ ep.tenant.vlanId ]
        else
          [ ]
      ) (builtins.attrValues (l.endpoints or { }))
    ) (builtins.attrNames links)
  );

  mkTenant4 = vid: "${tenantV4Base}.${toString vid}.0/24";
  mkTenant6 = vid: "${ulaPrefix}:${toString vid}::/64";

  coreTenantRoutes4 = builtins.map (vid: { dst = mkTenant4 vid; }) tenantVids;
  coreTenantRoutes6 = builtins.map (vid: { dst = mkTenant6 vid; }) tenantVids;

  coreRoutes4 = (coreEp.routes4 or [ ]) ++ coreTenantRoutes4;
  coreRoutes6 = (coreEp.routes6 or [ ]) ++ coreTenantRoutes6;

  policyUpstream4 =
    if defaultRouteMode == "default" && coreVia4 != null then
      [
        {
          dst = "0.0.0.0/0";
          via4 = coreVia4;
        }
      ]
    else
      [ ];

  policyUpstream6 =
    if defaultRouteMode == "default" && coreVia6 != null then
      [
        {
          dst = "::/0";
          via6 = coreVia6;
        }
      ]
    else
      [ ];

  policyRoutes4 = (policyEp.routes4 or [ ]) ++ policyUpstream4;
  policyRoutes6 = (policyEp.routes6 or [ ]) ++ policyUpstream6;

  endpoints1 = endpoints0 // {
    "${coreNodeName}" = coreEp // {
      routes4 = coreRoutes4;
      routes6 = coreRoutes6;
    };

    "${policyNodeName}" = policyEp // {
      routes4 = policyRoutes4;
      routes6 = policyRoutes6;
    };
  };

  policyCore1 = policyCore // {
    endpoints = endpoints1;
  };

  links1 = links // {
    "policy-core" = policyCore1;
  };

in
topo // { links = links1; }
