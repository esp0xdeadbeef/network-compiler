# FILE: ./lib/compile/assertions/default.nix
{ lib }:

topo:

let
  mode = topo.defaultRouteMode or "default";

  wanConsistency =
    import ./default-route-wan-consistency.nix { inherit lib; } topo;
in
{
  assertions =
    [
      {
        assertion = !(mode == "computed");
        message = ''
          defaultRouteMode = "computed" is not supported without explicit internet computation context.
        '';
      }
    ]
    ++ (wanConsistency.assertions or [ ]);
}

