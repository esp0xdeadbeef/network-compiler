{ lib, evalNetwork }:

let
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
      throw "Unsupported topology format";

in

path:
let
  raw0 = import path;
  raw = if builtins.isFunction raw0 then raw0 { } else raw0;
  sites = normalize raw;
in
lib.mapAttrs (_: siteCfg: if isResolvedTopo siteCfg then siteCfg else evalNetwork siteCfg) sites
