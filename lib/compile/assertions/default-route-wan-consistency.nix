# ./lib/compile/assertions/default-route-wan-consistency.nix
{ lib }:

topo:

let
  mode = if topo ? defaultRouteMode then topo.defaultRouteMode else "default";

  wanLinks = lib.filter (l: (l.kind or null) == "wan") (lib.attrValues (topo.links or { }));

  wanHasDefault = lib.any (
    l:
    lib.any (
      ep:
      (lib.any (r: (r.dst or null) == "0.0.0.0/0") (ep.routes4 or [ ]))
      || (lib.any (r: (r.dst or null) == "::/0") (ep.routes6 or [ ]))
    ) (lib.attrValues (l.endpoints or { }))
  ) wanLinks;

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
      assertion = !(mode == "default" && lib.length wanLinks > 0 && !wanHasDefault);
      message = ''
        defaultRouteMode = "default" requires at least one WAN link
        to advertise 0.0.0.0/0 or ::/0.
      '';
    }
  ];
}
