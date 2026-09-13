{ lib }:

{
  overlayEndpointNodes =
    overlays:
    lib.unique (
      builtins.concatLists (
        map (
          o:
          let
            t = o.terminateOn or null;
          in
          if builtins.isList t then
            t
          else if t == null then
            [ ]
          else
            [ t ]
        ) overlays
      )
    );
}
