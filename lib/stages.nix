{ lib }:

let
  flattenSites = import ./flatten-sites.nix { inherit lib; };
  normalizeSite = import ./normalize/from-user-input.nix { inherit lib; };

  splitSiteKey = import ./stages/split-site-key.nix { inherit lib; };
  regroupSites = import ./stages/regroup-sites.nix {
    inherit lib;
    splitSiteKey = splitSiteKey;
  };

  buildModel = import ./stages/build-model.nix { inherit lib; };
  compileSite = import ./stages/compile-site.nix { inherit lib normalizeSite buildModel; };

  canonicalize = import ./canonicalize.nix { inherit lib; };

in
{
  run =
    inputs:
    let
      sitesFlat = flattenSites inputs;
      compiledFlat = lib.mapAttrs compileSite sitesFlat;
      compiledGrouped = regroupSites compiledFlat;

      out = {
        sites = compiledGrouped;
        meta = {
          schemaVersion = 5;
          provenance = {
            originalInputs = inputs;
          };
        };
      };
    in
    canonicalize out;
}
