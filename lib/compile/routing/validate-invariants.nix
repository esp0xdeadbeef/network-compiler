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
  nodes = topo.nodes or { };

  tenantVids = lib.unique (
    lib.filter (x: x != null) (
      lib.concatMap (
        l:
        lib.concatMap (
          ep:
          let
            t = ep.tenant or null;
          in
          if builtins.isAttrs t && t ? vlanId then [ t.vlanId ] else [ ]
        ) (lib.attrValues (l.endpoints or { }))
      ) (lib.attrValues links)
    )
  );

  mkTenant4 = vid: "${tenantV4Base}.${toString vid}.0/24";
  mkTenant6 = vid: "${ulaPrefix}:${toString vid}::/64";

  tenant4s = map mkTenant4 tenantVids;
  tenant6s = map mkTenant6 tenantVids;

  isTenantDst = dst: (lib.elem dst tenant4s) || (lib.elem dst tenant6s);

  ifacesOf = n: (nodes.${n}.interfaces or { });

  routesOfIface = iface: (iface.routes4 or [ ]) ++ (iface.routes6 or [ ]);

  ifaceHasTenantRoute = iface: lib.any (r: isTenantDst (r.dst or "")) (routesOfIface iface);

  isCoreNode = n: n == coreNodeName || lib.hasPrefix "${coreNodeName}-" n;

  coreNodes = lib.filter isCoreNode (builtins.attrNames nodes);

  coreHasTenantRoutes = lib.any (
    n: lib.any ifaceHasTenantRoute (lib.attrValues (ifacesOf n))
  ) coreNodes;

  accessPrefix =
    if topo ? accessNodePrefix && builtins.isString topo.accessNodePrefix then
      topo.accessNodePrefix
    else
      "s-router-access";

  isAccessNode = n: lib.hasPrefix "${accessPrefix}-" n;

  accessNodes = lib.filter isAccessNode (builtins.attrNames nodes);

  accessOwnVid =
    n:
    let
      ps = lib.splitString "-" n;
      last = if ps == [ ] then "" else lib.last ps;
    in
    if builtins.match "^[0-9]+$" last == null then null else lib.toInt last;

  accessHasForeignTenantRoute =
    n:
    let
      own = accessOwnVid n;

      own4 = if own == null then null else mkTenant4 own;
      own6 = if own == null then null else mkTenant6 own;

      own4s = if own4 == null then "" else own4;
      own6s = if own6 == null then "" else own6;

      isForeign = dst: isTenantDst dst && dst != own4s && dst != own6s;
    in
    lib.any (iface: lib.any (r: isForeign (r.dst or "")) (routesOfIface iface)) (
      lib.attrValues (ifacesOf n)
    );

  anyAccessForeign = lib.any accessHasForeignTenantRoute accessNodes;

  linkMembers = l: lib.unique (l.members or [ ]);

  linkConnectsAccessWithoutPolicy =
    _lname: l:
    let
      ms = linkMembers l;
      hasPolicy = lib.elem policyNodeName ms;
      accessMs = lib.filter isAccessNode ms;
      hasAccess = accessMs != [ ];
      hasMultipleAccess = (lib.length accessMs) > 1;
      hasCore = lib.any isCoreNode ms;
      hasCoreWithoutPolicy = hasCore && !hasPolicy;
      hasAccessWithoutPolicy = hasAccess && !hasPolicy;
    in
    hasMultipleAccess || (hasAccessWithoutPolicy && hasCoreWithoutPolicy);

  badAccessConnectivity = lib.filterAttrs linkConnectsAccessWithoutPolicy links;

  tenantGatewayCountForNode =
    n:
    lib.length (
      lib.filter (
        iface:
        (iface.kind or null) == "lan"
        && (iface.gateway or false)
        && (iface.tenant or null) != null
        && builtins.isAttrs iface.tenant
        && iface.tenant ? vlanId
      ) (lib.attrValues (ifacesOf n))
    );

  multiTenantOwners = lib.filter (n: n != policyNodeName && (tenantGatewayCountForNode n) > 1) (
    builtins.attrNames nodes
  );

  _assertCoreNoTenant = lib.assertMsg (!coreHasTenantRoutes) ''
    Invariant violation: one or more core nodes contain tenant routes.

    Core routers (fabric host and core context nodes) must NEVER contain tenant prefixes.

    Core nodes considered:
      - ${lib.concatStringsSep "\n    - " coreNodes}
  '';

  _assertAccessNoForeign = lib.assertMsg (!anyAccessForeign) ''
    Invariant violation: an access node has a foreign tenant route.

    Access routers may only:
      - own their local tenant LAN (connected)
      - default to policy
    They must not route to other tenant prefixes directly.
  '';

  _assertPolicyRemovalDisconnects = lib.assertMsg (badAccessConnectivity == { }) ''
    Invariant violation: tenant-carrying nodes are connected without policy.

    Removing '${policyNodeName}' must make all tenant VLANs mutually unreachable.

    Offending link(s):
      - ${lib.concatStringsSep "\n    - " (builtins.attrNames badAccessConnectivity)}
  '';

  _assertSinglePolicyMultiTenant = lib.assertMsg (multiTenantOwners == [ ]) ''
    Invariant violation: non-policy node owns multiple tenant VLANs.

    Offending node(s):
      - ${lib.concatStringsSep "\n    - " multiTenantOwners}
  '';

in
builtins.seq _assertCoreNoTenant (
  builtins.seq _assertAccessNoForeign (
    builtins.seq _assertPolicyRemovalDisconnects (builtins.seq _assertSinglePolicyMultiTenant topo)
  )
)
