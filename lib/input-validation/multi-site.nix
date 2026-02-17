{ lib }:

sites:

let
  isSingleSiteInput =
    x:
    builtins.isAttrs x
    && x ? policyAccessTransitBase
    && x ? corePolicyTransitVlan
    && x ? ulaPrefix
    && x ? tenantV4Base;

  evalSingleSite = import ./single-site.nix { inherit lib; };

in
lib.mapAttrs (
  _: v:
  if isSingleSiteInput v then evalSingleSite v else throw "eval/multi-site: invalid site definition"
) sites
