{ nix }:

let
  lib =
    if nix ? lib then
      nix.lib
    else if nix ? inputs && nix.inputs ? nixpkgs && nix.inputs.nixpkgs ? lib then
      nix.inputs.nixpkgs.lib
    else
      throw "lib/main.nix: could not resolve nixpkgs lib";

  evalNetwork = import ./input-validation { inherit lib; };

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

  mkSiteResult = routed: {
    inherit routed;

    query = {
      all-nodes = builtins.attrNames routed.nodes;

      view-node = nodeName: (import ./query/view-node.nix { inherit lib; }) nodeName routed;

      node-context =
        args: (import ./query/node-context.nix { inherit lib; }) ({ inherit routed; } // args);

      wan = import ./query/wan.nix { inherit lib routed; };
      multi-wan = import ./query/multi-wan.nix { inherit lib routed; };
      routing-table = import ./query/routing-table.nix { inherit lib routed; };
    };
  };

in
{
  fromFile =
    path:
    let
      raw0 = import path;
      raw = if builtins.isFunction raw0 then raw0 { } else raw0;

      sites = normalize raw;

      routedBySite = lib.mapAttrs (
        _: siteCfg: if isResolvedTopo siteCfg then siteCfg else evalNetwork siteCfg
      ) sites;

      cleanedBySite = routedBySite;
    in
    {
      sites = cleanedBySite;

      query = {
        all-sites = builtins.attrNames cleanedBySite;

        all-nodes = lib.mapAttrs (_: r: builtins.attrNames r.nodes) cleanedBySite;

        site =
          siteName:
          if cleanedBySite ? "${siteName}" then
            mkSiteResult cleanedBySite.${siteName}
          else
            throw "unknown site '${siteName}'";
      };
    };
}
