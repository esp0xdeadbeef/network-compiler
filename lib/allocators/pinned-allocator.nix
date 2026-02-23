{ lib }:

let

  parseCidr =
    cidr:
    let
      parts = lib.splitString "/" cidr;
    in
    if builtins.length parts != 2 then
      throw "allocator: expected CIDR like a.b.c.d/prefix or xxxx::/prefix, got: ${toString cidr}"
    else
      {
        base = builtins.elemAt parts 0;
        prefix = lib.toInt (builtins.elemAt parts 1);
      };

  pow2 =
    n:
    if n < 0 then
      throw "allocator: pow2 exponent must be >= 0, got ${toString n}"
    else
      builtins.foldl' (acc: _: acc * 2) 1 (lib.range 1 n);

  ipv4ToInt =
    ip:
    let
      octets = lib.splitString "." ip;
      _ = if builtins.length octets != 4 then throw "allocator: invalid IPv4 address: ${ip}" else true;

      toOctet =
        s:
        let
          v = lib.toInt s;
        in
        if 0 <= v && v <= 255 then v else throw "allocator: IPv4 octet out of range in ${ip}";
      o0 = toOctet (builtins.elemAt octets 0);
      o1 = toOctet (builtins.elemAt octets 1);
      o2 = toOctet (builtins.elemAt octets 2);
      o3 = toOctet (builtins.elemAt octets 3);
    in
    (((o0 * 256) + o1) * 256 + o2) * 256 + o3;

  intToIpv4 =
    n:
    let
      _ =
        if n < 0 || n > 4294967295 then
          throw "allocator: IPv4 integer out of range: ${toString n}"
        else
          true;

      o3 = lib.mod n 256;
      n2 = (n - o3) / 256;
      o2 = lib.mod n2 256;
      n1 = (n2 - o2) / 256;
      o1 = lib.mod n1 256;
      n0 = (n1 - o1) / 256;
      o0 = n0;
    in
    "${toString o0}.${toString o1}.${toString o2}.${toString o3}";

  mkIPv4Allocator =
    pool:
    if pool == null || !(pool ? ipv4) || pool.ipv4 == null then
      (_: null)
    else
      let
        parsed = parseCidr pool.ipv4;
        baseInt = ipv4ToInt parsed.base;
        prefix = parsed.prefix;

        _ =
          if prefix < 0 || prefix > 32 then
            throw "allocator: IPv4 prefix must be in [0..32], got ${toString prefix} in ${pool.ipv4}"
          else
            true;

        size = pow2 (32 - prefix);

        alloc =
          idx:
          let
            off = idx + 1;
          in
          if off >= size then
            throw "allocator: IPv4 pool exhausted (${pool.ipv4}), idx=${toString idx}"
          else
            intToIpv4 (baseInt + off);
      in
      alloc;

  mkIPv6Allocator =
    pool:
    if pool == null || !(pool ? ipv6) || pool.ipv6 == null then
      (_: null)
    else
      let

        parsed = lib.network.ipv6.fromString pool.ipv6;

        first = lib.network.ipv6.firstAddress parsed;

        nthHost =
          idx:
          let
            steps = idx + 1;

            stepOnce =
              a:
              let
                n = lib.network.ipv6.nextAddress a;
              in
              if n == null then throw "allocator: IPv6 pool exhausted (${pool.ipv6}), idx=${toString idx}" else n;

            addrAttrs = builtins.foldl' (a: _: stepOnce a) first (lib.range 1 steps);
          in
          addrAttrs.address;
      in
      nthHost;

in
{
  inherit mkIPv4Allocator mkIPv6Allocator;
}
