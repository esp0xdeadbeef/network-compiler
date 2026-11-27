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

  inherit (self.constants) ipv6Bits ipv6PieceBits ipv6PieceMaxValue ipv6Pieces;
  inherit (self.parsers) expandIpv6 modList parseExpandedIpv6;
# `rec` because the definitions in this part refer to each other; cross-part
# references come in through `self` (they are mutually recursive as a group).
in
rec
{
  /**
    Parses an IPv6 address from a string to the internal representation (list
    of integers).

    # Type: string -> ipv6IR

    # Example:

    ```nix
    parseIpv6FromString "2001:DB8::ffff"
    => [8193 3512 0 0 0 0 0 65535]
    ```
  */
  parseIpv6FromString = addr: parseExpandedIpv6 (expandIpv6 addr);

  /**
    Converts an internal representation of an IPv6 address (i.e, a list
    of integers) to a string. The returned string is not a canonical
    representation as defined in RFC 5952, i.e zeros are not compressed.

    # Type: ipv6IR -> string

    # Example:

    ```nix
    parseIpv6FromString [8193 3512 0 0 0 0 0 65535]
    => "2001:db8:0:0:0:0:0:ffff"
    ```
  */
  toStringFromExpandedIp =
    pieces:
    assert lib.assertMsg (
      length pieces == ipv6Pieces
    ) "toStringFromExpandedIp: expected a list with ${ipv6Pieces}";
    (strings.concatMapStringsSep ":" (piece: strings.toLower (trivial.toHexString piece)) pieces);

  /**
    Raises `base` to the power of `exponent`.

    # Type: int -> int -> int

    ```nix
    pow 2 3
    => 8
    ```
  */
  pow =
    base: exponent:
    if exponent < 0 then
      throw "lib.network.pow: Exponent cannot be negative."
    else if exponent == 0 then
      1
    else
      lists.foldl' (acc: _: acc * base) 1 (lists.range 1 exponent);
  /**
    Calculates the first address in a subnet.

    # Type: ipv6IR -> int -> ipv6IR

    ```nix
    calculateFirstAddress [8193 3512 0 0 0 0 0 65535] 16
    => [8193 0 0 0 0 0 0 0]
    ```
  */
  calculateFirstAddress =
    addr: prefixLength:
    let
      prefixMask = lists.imap0 (
        idx: piece:
        # Generate a decimal number, which in binary format will have the format "1111111100000000", where the number of ones is equal to `bits'.
        let
          bits = trivial.min (trivial.max (prefixLength - ipv6PieceBits * idx) 0) ipv6PieceBits;
          # 2^n - 2^(n-k) to pad k bits with ones on the left.
          maskForPiece = (pow 2 ipv6PieceBits) - (pow 2 (ipv6PieceBits - bits));
        in
        maskForPiece
      ) addr;

      firstAddress = lists.zipListsWith (l: r: trivial.bitAnd l r) addr prefixMask;
    in
    firstAddress;

  /**
    Calculates the last address in a subnet.

    # Type: ipv6IR -> int -> ipv6IR

    ```nix
    calculateLastAddress [8193 3512 0 0 0 0 0 65535] 16
    => [8193 65535 65535 65535 65535 65535 65535 65535]
    ```
  */
  calculateLastAddress =
    addr: prefixLength:
    let
      suffixLength = ipv6Bits - prefixLength;
      suffixMask = lists.imap0 (
        idx: piece:
        # Generate a decimal number, which in binary format will have the format "0000000011111111", where the number of ones is equal to `bits'.
        let
          bits = trivial.min (trivial.max (
            suffixLength - ipv6PieceBits * (ipv6Pieces - idx - 1)
          ) 0) ipv6PieceBits;
          # 2^n - 1 to pad k bits with ones on the right.
          maskForPiece = (pow 2 bits) - 1;
        in
        maskForPiece
      ) addr;

      lastAddress = lists.zipListsWith (l: r: trivial.bitOr l r) addr suffixMask;
    in
    lastAddress;

  /**
    Calculates the next address. Returns null if the passed address is the
    last one.

    # Type: ipv6IR -> int -> ipv6IR

    # Example:

    ```nix
    calculateNextAddress [8193 3512 0 0 0 0 0 65535]
    => [8193 3512 0 0 0 0 1 0]
    ```
  */
  calculateNextAddress =
    addr: prefixLength:
    if addr == calculateLastAddress addr prefixLength then
      null
    else
      let
        # Add one to the last piece of the address, then take the modulus - if
        # it's greater than 65535, make it 0 and add one to the penultimate piece.
        newAddr = (lists.take (length addr - 1) addr) ++ [ (lists.last addr + 1) ];
        nextAddr = modList (ipv6PieceMaxValue + 1) newAddr;
      in
      nextAddr;
}
