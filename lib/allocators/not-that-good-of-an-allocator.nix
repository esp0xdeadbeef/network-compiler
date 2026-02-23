{ lib }:

let

  parseCidr =
    cidr:
    let
      parts = lib.splitString "/" cidr;
    in
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
