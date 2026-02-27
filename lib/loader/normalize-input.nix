{ lib, evalNetwork }:

let
  err = import ../error.nix { inherit lib; };

  isSingleInput =
    x:
    builtins.isAttrs x
    && x ? policyAccessTransitBase
    && x ? corePolicyTransitVlan
    && x ? ulaPrefix
    && x ? tenantV4Base;

  isResolvedTopo =
    x: builtins.isAttrs x && x ? nodes && x ? links && x ? ulaPrefix && x ? tenantV4Base;

  normalize =
    raw:
    if isSingleInput raw || isResolvedTopo raw then
      { default = raw; }
    else if builtins.isAttrs raw then
      raw
    else
      err.throwError {
        code = "E_INPUT_UNSUPPORTED_TOPOLOGY_FORMAT";
        site = null;
        path = [ ];
        message = "unsupported topology format";
        hints = [
          "Input must be an attribute set (single site or multi-site)."
          "If passing a single site, include: policyAccessTransitBase, corePolicyTransitVlan, ulaPrefix, tenantV4Base."
          "If passing a resolved topology, include: nodes, links, ulaPrefix, tenantV4Base."
        ];
      };

in

path:
let
  raw0 = import path;
  raw = if builtins.isFunction raw0 then raw0 { } else raw0;
  sites = normalize raw;
in
lib.mapAttrs (_: siteCfg: if isResolvedTopo siteCfg then siteCfg else evalNetwork siteCfg) sites
