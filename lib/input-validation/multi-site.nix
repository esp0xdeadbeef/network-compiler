{ lib }:

sites:

let
  err = import ../error.nix { inherit lib; };

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
  siteName: v:
  if isSingleSiteInput v then
    evalSingleSite v
  else
    err.throwError {
      code = "E_INPUT_INVALID_SITE_DEFINITION";
      site = siteName;
      path = [ siteName ];
      message = "invalid site definition in multi-site input";
      hints = [
        "Each site must contain: policyAccessTransitBase, corePolicyTransitVlan, ulaPrefix, tenantV4Base."
        "If you already have a resolved topology, pass it through the resolved-topology entrypoint instead."
      ];
    }
) sites
