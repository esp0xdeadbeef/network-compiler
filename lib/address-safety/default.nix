{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure throwError;
  parse = import ./parse.nix { inherit lib ensure throwError; };
  overlap = import ./overlaps.nix { inherit lib throwError; };
  inherit (parse) parseAny;
  inherit (overlap) assertNoOverlaps assertNoCrossOverlaps;

  validateSite =
    siteKey: declared:
    let
      ownership = declared.ownership or { };
      prefixes0 = ownership.prefixes or [ ];

      tenantCidrs = lib.concatMap (
        p:
        lib.filter (x: x != null) [
          (p.ipv4 or null)
          (p.ipv6 or null)
        ]
      ) prefixes0;

      tenantRangesAll = map parseAny tenantCidrs;
      tenantRangesV4 = lib.filter (r: r.version == 4) tenantRangesAll;
      tenantRangesV6 = lib.filter (r: r.version == 6) tenantRangesAll;

      pools = declared.pools or { };

      poolCidrs = lib.concatMap (
        pool:
        lib.filter (x: x != null) [
          (pool.ipv4 or null)
          (pool.ipv6 or null)
        ]
      ) (builtins.attrValues pools);

      poolRangesAll = map parseAny poolCidrs;
      poolRangesV4 = lib.filter (r: r.version == 4) poolRangesAll;
      poolRangesV6 = lib.filter (r: r.version == 6) poolRangesAll;

      _tenNoOverlapV4 = assertNoOverlaps "tenant IPv4 prefixes (site '${siteKey}')" tenantRangesV4;

      _tenNoOverlapV6 = assertNoOverlaps "tenant IPv6 prefixes (site '${siteKey}')" tenantRangesV6;

      _poolNoOverlapV4 = assertNoOverlaps "address pool IPv4 ranges (site '${siteKey}')" poolRangesV4;

      _poolNoOverlapV6 = assertNoOverlaps "address pool IPv6 ranges (site '${siteKey}')" poolRangesV6;

      _crossNoOverlapV4 =
        assertNoCrossOverlaps "tenant/pool IPv4 overlap (site '${siteKey}')" tenantRangesV4
          poolRangesV4;

      _crossNoOverlapV6 =
        assertNoCrossOverlaps "tenant/pool IPv6 overlap (site '${siteKey}')" tenantRangesV6
          poolRangesV6;
    in
    true;
in
{
  inherit validateSite;
}
