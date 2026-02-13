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
  ];
}
