# ./lib/compile/assertions/default-route-wan-consistency.nix
{ lib }:

topo:

let
  mode = topo.defaultRouteMode or "default";

  wanLinks = lib.filter (l: (l.kind or null) == "wan") (lib.attrValues (topo.links or { }));

  wanEndpoints = lib.concatMap (l: lib.attrValues (l.endpoints or { })) wanLinks;

  wanDsts = lib.concatMap (
    ep: (map (r: r.dst or null) (ep.routes4 or [ ])) ++ (map (r: r.dst or null) (ep.routes6 or [ ]))
  ) wanEndpoints;

  wanHasDefault = lib.elem "0.0.0.0/0" wanDsts || lib.elem "::/0" wanDsts;

  # Require a usable next-hop when a WAN endpoint advertises a default route,
  # unless it's explicitly learned via DHCP/RA.
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

  wanDefaultsHaveNextHop =
    lib.all epHasUsableDefault wanEndpoints;

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
  ];
}

