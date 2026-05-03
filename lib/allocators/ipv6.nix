{ lib, err }:

let
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
  inherit mkIPv6Allocator;
}
