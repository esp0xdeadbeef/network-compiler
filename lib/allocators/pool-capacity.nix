{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) throwError;

  splitCidr =
    siteKey: poolPath: cidr:
    let
      parts = lib.splitString "/" cidr;
    in
    if builtins.length parts != 2 then
      throwError {
        code = "E_ALLOCATOR_INVALID_CIDR";
        site = siteKey;
        path = poolPath;
        message = "expected CIDR like a.b.c.d/prefix or xxxx::/prefix, got '${toString cidr}'";
        hints = [ "Use a valid CIDR string with exactly one '/'." ];
      }
    else
      {
        base = builtins.elemAt parts 0;
        prefix = lib.toInt (builtins.elemAt parts 1);
      };

  familyBits = family: if family == 4 then 32 else 128;

  isRightFamily =
    family: base:
    if family == 4 then builtins.match "[0-9.]+" base != null else builtins.match ".*:.*" base != null;

  validatePool =
    {
      siteKey,
      poolPath,
      family,
      pool, # { ipv4 | ipv6 } or null
      requiredHosts,
      required ? false,
    }:
    let
      cidr =
        if pool == null then
          null
        else if family == 4 then
          pool.ipv4 or null
        else
          pool.ipv6 or null;
    in
    if cidr == null then
      if required || requiredHosts > 0 then
        throwError {
          code = "E_ALLOCATOR_POOL_MISSING";
          site = siteKey;
          path = poolPath;
          message = "required IPv${toString family} address pool is missing (requiredHosts=${toString requiredHosts})";
          hints = [
            "Add pools.${if family == 4 then "p2p/loopback" else "p2p/loopback"}.ipv${toString family}."
          ];
        }
      else
        true
    else
      let
        parsed = splitCidr siteKey poolPath cidr;
        bits = familyBits family;
        hostBits = bits - parsed.prefix;

        capacity = builtins.foldl' (acc: _: acc * 2) 1 (lib.range 1 hostBits);
        _family =
          if !isRightFamily family parsed.base then
            throwError {
              code = "E_ALLOCATOR_INVALID_IPV4";
              site = siteKey;
              path = poolPath;
              message = "expected IPv${toString family} CIDR, got '${toString cidr}'";
              hints = [ "Use an address of the right family." ];
            }
          else
            true;
        _prefix =
          if parsed.prefix < 0 || parsed.prefix > bits then
            throwError {
              code = "E_ALLOCATOR_INVALID_PREFIX";
              site = siteKey;
              path = poolPath;
              message = "IPv${toString family} prefix must be in [0..${toString bits}], got /${toString parsed.prefix} in '${cidr}'";
              hints = [ "Use a valid prefix length." ];
            }
          else
            true;
        _capacity =
          if requiredHosts <= 0 || capacity >= requiredHosts then
            true
          else
            throwError {
              code = "E_ALLOCATOR_POOL_EXHAUSTED";
              site = siteKey;
              path = poolPath;
              message = "IPv${toString family} pool '${cidr}' has ${toString capacity} addresses but ${toString requiredHosts} are required";
              hints = [
                "Use a shorter prefix (e.g. /23 instead of /24)."
                "Or reduce the number of modeled nodes / adjacencies."
              ];
            };
      in
      builtins.seq _family (builtins.seq _prefix _capacity);

in
{
  inherit validatePool familyBits;

  validateSite =
    {
      siteKey,
      transitLinks,
      nodeCount,
      addressPools,
    }:
    let
      p2pRequired = 2 * (builtins.length transitLinks);
      loopbackRequired = nodeCount;
    in
    builtins.seq
      (validatePool {
        inherit siteKey;
        poolPath = [
          "addressPools"
          "p2p"
        ];
        family = 4;
        pool = addressPools.p2p or null;
        requiredHosts = p2pRequired;
        required = true;
      })
      (validatePool {
        inherit siteKey;
        poolPath = [
          "addressPools"
          "local"
        ];
        family = 4;
        pool = addressPools.local or null;
        requiredHosts = loopbackRequired;
      });
}
