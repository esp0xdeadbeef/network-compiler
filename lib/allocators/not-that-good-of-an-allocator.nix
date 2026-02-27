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
        prefix = builtins.elemAt parts 1;
      };

  mkIPv4Allocator =
    pool:
    if pool == null || !(pool ? ipv4) then
      (_: null)
    else
      let
        parsed = parseCidr pool.ipv4;
        ipParts = lib.splitString "." parsed.base;
        _ =
          if builtins.length ipParts < 3 then
            err.throwError {
              code = "E_ALLOCATOR_INVALID_IPV4_BASE";
              site = null;
              path = [
                "addressPools"
                "local"
                "ipv4"
              ];
              message = "invalid IPv4 base address in '${toString pool.ipv4}'";
              hints = [ "Use a CIDR with an IPv4 base like 10.0.0.0/24." ];
            }
          else
            true;
        a = builtins.elemAt ipParts 0;
        b = builtins.elemAt ipParts 1;
        c = builtins.elemAt ipParts 2;
      in
      idx: "${a}.${b}.${c}.${toString (idx + 1)}";

  mkIPv6Allocator =
    pool:
    if pool == null || !(pool ? ipv6) then
      (_: null)
    else
      let
        parsed = parseCidr pool.ipv6;
        base = parsed.base;
      in
      idx: "${base}${toString (idx + 1)}";

in
{
  inherit mkIPv4Allocator mkIPv6Allocator;
}
