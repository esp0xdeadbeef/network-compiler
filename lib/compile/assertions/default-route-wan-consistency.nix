{ lib }:

topo:

let
  mode = topo.defaultRouteMode or "default";

  tenantV4Base = topo.tenantV4Base or null;
  ulaPrefix = topo.ulaPrefix or null;

  wanLinks = lib.filter (l: (l.kind or null) == "wan") (lib.attrValues (topo.links or { }));

  wanEndpoints = lib.concatMap (l: lib.attrValues (l.endpoints or { })) wanLinks;

  wanDsts = lib.concatMap (
    ep: (map (r: r.dst or null) (ep.routes4 or [ ])) ++ (map (r: r.dst or null) (ep.routes6 or [ ]))
  ) wanEndpoints;

  wanHasDefault = lib.elem "0.0.0.0/0" wanDsts || lib.elem "::/0" wanDsts;

  epHasUsableDefault =
    ep:
    let
      r4 = ep.routes4 or [ ];
      r6 = ep.routes6 or [ ];

      hasDefault4 = lib.any (r: (r.dst or null) == "0.0.0.0/0") r4;
      hasDefault6 = lib.any (r: (r.dst or null) == "::/0") r6;

      ok4 =
        (!hasDefault4)
        || lib.any (r: (r.dst or null) == "0.0.0.0/0" && (r ? via4) && r.via4 != null) r4
        || (ep.dhcp or false);

      ok6 =
        (!hasDefault6)
        || lib.any (r: (r.dst or null) == "::/0" && (r ? via6) && r.via6 != null) r6
        || (ep.acceptRA or false)
        || (ep.dhcp or false);
    in
    ok4 && ok6;

  wanDefaultsHaveNextHop = lib.all epHasUsableDefault wanEndpoints;

  isTenant4 =
    dst:
    if tenantV4Base == null || dst == null then
      false
    else
      lib.hasPrefix "${tenantV4Base}." dst && lib.hasSuffix "/24" dst;

  isTenant6 =
    dst:
    if ulaPrefix == null || dst == null then
      false
    else
      (lib.hasPrefix "${ulaPrefix}:" dst && lib.hasSuffix "/64" dst) || dst == "${ulaPrefix}::/48";

  wanHasTenantReachability = lib.any (dst: isTenant4 dst || isTenant6 dst) wanDsts;

in
{
  assertions = [
    {
      assertion = !(mode == "blackhole" && wanHasDefault);
      message = ''
        defaultRouteMode = "blackhole" forbids default routes on WAN links.

        Remove any 0.0.0.0/0 or ::/0 routes from WAN endpoints.
      '';
    }

    {
      assertion = !(mode == "default" && !wanHasDefault);
      message = ''
        defaultRouteMode = "default" requires at least one WAN endpoint to advertise
        a default route (0.0.0.0/0 or ::/0).

        No WAN endpoints include 0.0.0.0/0 or ::/0 in routes4/routes6.
      '';
    }

    {
      assertion = !(wanHasDefault && !wanDefaultsHaveNextHop);
      message = ''
        A WAN endpoint advertises a default route (0.0.0.0/0 or ::/0) without a usable next-hop.

        For static default routes, set:
          - routes4 = [ { dst = "0.0.0.0/0"; via4 = "<upstream-v4-gw>"; } ];
          - routes6 = [ { dst = "::/0"; via6 = "<upstream-v6-gw>"; } ];

        Or enable DHCP / IPv6 RA learning on that WAN endpoint (dhcp=true / acceptRA=true).
      '';
    }

    {
      assertion = !wanHasTenantReachability;
      message = ''
        WAN endpoints must NOT advertise or install tenant/internal reachability (no /24 tenant v4, no /64 tenant ULA, no ULA /48).

        Fix by removing tenant-specific routes from WAN endpoints (WAN must be default-only).
      '';
    }
  ];
}
