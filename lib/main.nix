{ nix }:

let
  lib = import ./lib/recursivelyImport.nix { inherit nix; };

  compile = import ./from-inputs.nix { inherit lib; };

  mkSite = import ./runtime/site-runtime.nix { inherit lib; };

in
{
  fromFile =
    path:
    let
      inputs = import path;
      sites = compile inputs;
    in
    {
      inherit sites;

      query = {
        all-sites = builtins.attrNames sites;
        all-nodes = lib.mapAttrs (_: r: builtins.attrNames r.nodes) sites;

        site = name: if sites ? "${name}" then mkSite sites.${name} else throw "unknown site '${name}'";
      };
    };
}
