{ lib }:

topo:

let
  mode = if topo ? defaultRouteMode then topo.defaultRouteMode else "default";

  allowedModes = [
    "default"
    "computed"
    "blackhole"
  ];

  hasWan = lib.any (l: (l.kind or null) == "wan") (lib.attrValues (topo.links or { }));

in
{
  assertions = [
    {
      assertion = lib.elem mode allowedModes;
      message = ''
        Invalid defaultRouteMode "${mode}".

        Allowed values:
          - "default"
          - "computed"
          - "blackhole"
      '';
    }

    {
      assertion = !(mode == "computed" && !hasWan);
      message = ''
        defaultRouteMode = "computed" requires at least one WAN link.

        No links with kind = "wan" were found in topology.
      '';
    }
  ];
}
