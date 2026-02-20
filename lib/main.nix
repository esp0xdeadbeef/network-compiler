{ nix }:

let
  lib = import ./lib/resolve-lib.nix { inherit nix; };

  evalNetwork = import ./input-validation { inherit lib; };

  loadSites = import ./loader/normalize-input.nix {
    inherit lib evalNetwork;
  };

  mkSite = import ./runtime/site-runtime.nix { inherit lib; };

in
{
  fromFile =
    path:
    let
      routedBySite = loadSites path;
    in
    {
      sites = routedBySite;

      query = {
        all-sites = builtins.attrNames routedBySite;

        all-nodes = lib.mapAttrs (_: r: builtins.attrNames r.nodes) routedBySite;

        site =
          name:
          if routedBySite ? "${name}" then mkSite routedBySite.${name} else throw "unknown site '${name}'";
      };
    };
}
