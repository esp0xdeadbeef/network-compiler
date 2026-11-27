{ lib, self }:
let
  inherit (builtins)
    map
    match
    genList
    length
    concatMap
    head
    toString
    ;

  inherit (lib) lists strings trivial;

# `rec` because the definitions in this part refer to each other; cross-part
# references come in through `self` (they are mutually recursive as a group).
in
rec
{
  ipv6Bits = 128;
  ipv6Pieces = 8; # 'x:x:x:x:x:x:x:x'
  ipv6PieceBits = 16; # One piece in range from 0 to 0xffff.
  ipv6PieceMaxValue = 65535; # 2^16 - 1
}
