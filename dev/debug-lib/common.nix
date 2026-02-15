{
  cfg,
}:

let
  flake = builtins.getFlake (toString ../../.);
  lib = flake.lib;
in
{
  inherit flake lib cfg;
}
