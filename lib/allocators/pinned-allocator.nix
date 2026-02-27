{ lib }:

let
  err = import ../error.nix { inherit lib; };

  parseCidr =
    cidr:
    let
      parts = lib.splitString "/" cidr;
    in
    if builtins.length parts != 2 then
      err.throwError {
        code = "E_ALLOCATOR_INVALID_CIDR";
        site = null;
        path = [ "addressPools" ];
        message = "expected CIDR like a.b.c.d/prefix or xxxx::/prefix, got '${toString cidr}'";
        hints = [ "Use a valid CIDR string with exactly one '/'." ];
      }
    else
      {
        base = builtins.elemAt parts 0;
        prefix = lib.toInt (builtins.elemAt parts 1);
      };

  pow2 =
    n:
    if n < 0 then
      err.throwError {
        code = "E_ALLOCATOR_INTERNAL";
        site = null;
        path = [ "addressPools" ];
        message = "pow2 exponent must be >= 0, got ${toString n}";
        hints = [ "This is an internal bug: exponent is derived from prefix math." ];
      }
    else
      builtins.foldl' (acc: _: acc * 2) 1 (lib.range 1 n);

  ipv4ToInt =
    ip:
    let
      octets = lib.splitString "." ip;
      _ =
        if builtins.length octets != 4 then
          err.throwError {
            code = "E_ALLOCATOR_INVALID_IPV4";
            site = null;
            path = [
              "addressPools"
              "local"
              "ipv4"
            ];
            message = "invalid IPv4 address '${ip}'";
            hints = [ "Use a valid IPv4 base like 10.0.0.0." ];
          }
        else
          true;

      toOctet =
        s:
        let
          v = lib.toInt s;
        in
        if 0 <= v && v <= 255 then
          v
        else
          err.throwError {
            code = "E_ALLOCATOR_INVALID_IPV4";
            site = null;
            path = [
              "addressPools"
              "local"
              "ipv4"
            ];
            message = "IPv4 octet out of range in '${ip}'";
            hints = [ "Each octet must be 0..255." ];
          };
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
          err.throwError {
            code = "E_ALLOCATOR_INVALID_IPV4";
            site = null;
            path = [
              "addressPools"
              "local"
              "ipv4"
            ];
            message = "IPv4 integer out of range: ${toString n}";
            hints = [ "This is an internal allocator bug (address math overflow)." ];
          }
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
            err.throwError {
              code = "E_ALLOCATOR_INVALID_PREFIX";
              site = null;
              path = [
                "addressPools"
                "local"
                "ipv4"
              ];
              message = "IPv4 prefix must be in [0..32], got ${toString prefix} in '${pool.ipv4}'";
              hints = [ "Use a valid IPv4 CIDR prefix /0..../32." ];
            }
          else
            true;

        size = pow2 (32 - prefix);

        alloc =
          idx:
          let
            off = idx + 1;
          in
          if off >= size then
            err.throwError {
              code = "E_ALLOCATOR_POOL_EXHAUSTED";
              site = null;
              path = [
                "addressPools"
                "local"
                "ipv4"
              ];
              message = "IPv4 pool exhausted ('${pool.ipv4}'), idx=${toString idx}";
              hints = [
                "Increase the pool size (use a shorter prefix, e.g. /23 instead of /24)."
                "Or reduce the number of allocated units."
              ];
            }
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
              if n == null then
                err.throwError {
                  code = "E_ALLOCATOR_POOL_EXHAUSTED";
                  site = null;
                  path = [
                    "addressPools"
                    "local"
                    "ipv6"
                  ];
                  message = "IPv6 pool exhausted ('${pool.ipv6}'), idx=${toString idx}";
                  hints = [
                    "Increase the IPv6 pool size (use a shorter prefix)."
                    "Or reduce the number of allocated units."
                  ];
                }
              else
                n;

            addrAttrs = builtins.foldl' (a: _: stepOnce a) first (lib.range 1 steps);
          in
          addrAttrs.address;
      in
      nthHost;

in
{
  inherit mkIPv4Allocator mkIPv6Allocator;
}
