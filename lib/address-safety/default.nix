{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure throwError;

  parseIPv4 =
    cidr:
    let
      parts = lib.splitString "/" cidr;
      _len = ensure (builtins.length parts == 2) {
        code = "E_ADDR_INVALID_CIDR";
        site = null;
        path = [
          "ownership"
          "prefixes"
        ];
        message = "invalid IPv4 CIDR '${toString cidr}'";
        hints = [ "Use a.b.c.d/prefix." ];
      };

      base = builtins.elemAt parts 0;
      prefix = lib.toInt (builtins.elemAt parts 1);

      octets = lib.splitString "." base;
      _octLen = ensure (builtins.length octets == 4) {
        code = "E_ADDR_INVALID_IPV4";
        site = null;
        path = [
          "ownership"
          "prefixes"
        ];
        message = "invalid IPv4 address '${base}'";
        hints = [ "Use four octets a.b.c.d." ];
      };

      toOctet =
        s:
        let
          v = lib.toInt s;
        in
        if 0 <= v && v <= 255 then
          v
        else
          throwError {
            code = "E_ADDR_INVALID_IPV4";
            site = null;
            path = [
              "ownership"
              "prefixes"
            ];
            message = "IPv4 octet out of range in '${base}'";
            hints = [ "Each octet must be 0..255." ];
          };

      o0 = toOctet (builtins.elemAt octets 0);
      o1 = toOctet (builtins.elemAt octets 1);
      o2 = toOctet (builtins.elemAt octets 2);
      o3 = toOctet (builtins.elemAt octets 3);

      _pref = ensure (0 <= prefix && prefix <= 32) {
        code = "E_ADDR_INVALID_PREFIX";
        site = null;
        path = [
          "ownership"
          "prefixes"
        ];
        message = "IPv4 prefix must be in [0..32] in '${cidr}'";
        hints = [ "Use /0..../32." ];
      };

      baseInt = (((o0 * 256) + o1) * 256 + o2) * 256 + o3;

      size = builtins.foldl' (acc: _: acc * 2) 1 (lib.range 1 (32 - prefix));

      start = baseInt;
      end = baseInt + size - 1;
    in
    {
      inherit start end prefix;
      version = 4;
      raw = cidr;
    };

  parseIPv6 =
    cidr:
    let
      parsed = lib.network.ipv6.fromString cidr;

      first = lib.network.ipv6.firstAddress parsed;
      last = lib.network.ipv6.lastAddress parsed;

      toInt = a: builtins.foldl' (acc: part: acc * 65536 + part) 0 a.address;

      start = toInt first;
      end = toInt last;
    in
    {
      inherit start end;
      version = 6;
      raw = cidr;
    };

  parseAny = cidr: if lib.hasInfix ":" cidr then parseIPv6 cidr else parseIPv4 cidr;

  overlaps = a: b: !(a.end < b.start || b.end < a.start);

  assertNoOverlaps =
    what: ranges:
    let
      sorted = lib.sort (a: b: a.start < b.start) ranges;

      check =
        prev: rest:
        if rest == [ ] then
          true
        else
          let
            cur = builtins.head rest;
          in
          if overlaps prev cur then
            throwError {
              code = "E_ADDR_OVERLAP";
              site = null;
              path = [ "address" ];
              message = "overlapping ${what}: '${prev.raw}' and '${cur.raw}'";
              hints = [ "Ensure CIDRs do not overlap." ];
            }
          else
            check cur (builtins.tail rest);
    in
    if sorted == [ ] then true else check (builtins.head sorted) (builtins.tail sorted);

  assertNoCrossOverlaps =
    what: left: right:
    let
      checkOne =
        a:
        map (
          b:
          if overlaps a b then
            throwError {
              code = "E_ADDR_OVERLAP";
              site = null;
              path = [ "address" ];
              message = "overlapping ${what}: '${a.raw}' and '${b.raw}'";
              hints = [ "Separate pool ranges from tenant prefixes." ];
            }
          else
            true
        ) right;
    in
    map checkOne left;

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
