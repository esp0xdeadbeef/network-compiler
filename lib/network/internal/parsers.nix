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

  inherit (self.constants) ipv6PieceMaxValue ipv6Pieces;
# `rec` because the definitions in this part refer to each other; cross-part
# references come in through `self` (they are mutually recursive as a group).
in
rec
{
  /**
    Expand an IPv6 address by removing the "::" compression and padding them
    with the necessary number of zeros. Converts an address from the string to
    the list of strings which then can be parsed using `_parseExpanded`.
    Throws an error when the address is malformed.

    # Type: string -> [ string ]

    # Example:

    ```nix
    expandIpv6 "2001:DB8::ffff"
    => ["2001" "DB8" "0" "0" "0" "0" "0" "ffff"]
    ```
  */
  expandIpv6 =
    addr:
    if match "^[0-9A-Fa-f:]+$" addr == null then
      throw "${addr} contains malformed characters for IPv6 address"
    else
      let
        pieces = strings.splitString ":" addr;
        piecesNoEmpty = lists.remove "" pieces;
        piecesNoEmptyLen = length piecesNoEmpty;
        zeros = genList (_: "0") (ipv6Pieces - piecesNoEmptyLen);
        hasPrefix = strings.hasPrefix "::" addr;
        hasSuffix = strings.hasSuffix "::" addr;
        hasInfix = strings.hasInfix "::" addr;
      in
      if addr == "::" then
        zeros
      else if
        let
          emptyCount = length pieces - piecesNoEmptyLen;
          emptyExpected =
            # splitString produces two empty pieces when "::" in the beginning
            # or in the end, and only one when in the middle of an address.
            if hasPrefix || hasSuffix then
              2
            else if hasInfix then
              1
            else
              0;
        in
        emptyCount != emptyExpected
        || (hasInfix && piecesNoEmptyLen >= ipv6Pieces) # "::" compresses at least one group of zeros.
        || (!hasInfix && piecesNoEmptyLen != ipv6Pieces)
      then
        throw "${addr} is not a valid IPv6 address"
      # Create a list of 8 elements, filling some of them with zeros depending
      # on where the "::" was found.
      else if hasPrefix then
        zeros ++ piecesNoEmpty
      else if hasSuffix then
        piecesNoEmpty ++ zeros
      else if hasInfix then
        concatMap (piece: if piece == "" then zeros else [ piece ]) pieces
      else
        pieces;

  /**
    Parses an expanded IPv6 address (see `expandIpv6`), converting each part
    from a string to an u16 integer. Returns an internal representation of IPv6
    address (list of integers) that can be easily processed by other helper
    functions.
    Throws an error some element is not an u16 integer.

    # Type: [ string ] -> ipv6IR

    # Example:

    ```nix
    parseExpandedIpv6 ["2001" "DB8" "0" "0" "0" "0" "0" "ffff"]
    => [8193 3512 0 0 0 0 0 65535]
    ```
  */
  parseExpandedIpv6 =
    addr:
    assert lib.assertMsg (
      length addr == ipv6Pieces
    ) "parseExpandedIpv6: expected list of integers with ${toString ipv6Pieces} elements";
    let
      u16FromHexStr =
        hex:
        let
          parsed = trivial.fromHexString hex;
        in
        if 0 <= parsed && parsed <= ipv6PieceMaxValue then
          parsed
        else
          throw "0x${hex} is not a valid u16 integer";
    in
    map (piece: u16FromHexStr piece) addr;

  /**
    Returns a new list where each element is taken modulo `mod`. The algorithm
    starts with the last element, the last element becomes the remainder of `mod`
    and adds an quotient part to the previous element.

    # Type: int -> [ int ] -> [ int ]

    # Example:

    ```nix
    modList 10 [9 10]
    => [1 0 0]
    modList 3 [1 2 10]
    => [2 2 1]
    ```
  */
  modList =
    mod: list:
    assert lib.assertMsg (mod > 0) "modList: module must be positive integer";
    let
      modListRec =
        add: mod: list:
        let
          listLen = length list;
        in
        if listLen == 0 then
          if add == 0 then [ ] else [ add ]
        else
          # Create a new list. The last element is the remainder and add the
          # quotient to the previous element.
          let
            newValue = lists.last list + add;
            newList = lists.take (listLen - 1) list;
          in
          let
            quot = newValue / mod;
            rem = trivial.mod newValue mod;
            prefix = modListRec quot mod newList;
          in
          prefix ++ [ rem ];
    in
    modListRec 0 mod list;
}
