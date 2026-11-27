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

  inherit (self.constants) ipv6Bits;
  inherit (self.parsers) modList;
  inherit (self.addresses) calculateFirstAddress calculateLastAddress calculateNextAddress parseIpv6FromString toStringFromExpandedIp;
# `rec` because the definitions in this part refer to each other; cross-part
# references come in through `self` (they are mutually recursive as a group).
in
rec
{
  _common = {
    inherit modList;
  };

  /*
    Internally, an IPv6 address is stored as a list of 16-bit integers with
    8 elements. Wherever you see `ipv6IR` (ipv6 internal representation) in
    internal functions docs, it means that it is a list of integers produced by
    one of the internal parsers, such as `parseIpv6FromString`
  */
  _ipv6 = {
    inherit calculateFirstAddress calculateLastAddress calculateNextAddress;

    /*
      Creates ipv6AddrAttrs. The returned attr set contains most of the basic
      fields that a user wants to get from an address, such as the URL-formatted
      address, prefix length, etc.

      We can't just update the attrset because it contains `address` and
      `addressCidr` strings that depend on the internal address, so when we
      update the address we need to update all the fields.

      # Type: ipv6IR -> int -> ipv6AddrAttrs

      # Example:

      ```nix
      makeIpv6Type [65535 0 0 0 0 0 0 0] 32
      => {
        address = "ffff:0:0:0:0:0:0:0";
        address = "ffff:0:0:0:0:0:0:0/32";
        url = "[2001:db8:0:0:0:0:0:ffff]";
        urlWithPort = int -> string;
        prefixLength = 32;
        _address = [65535 0 0 0 0 0 0 0];
      }
      ```
    */
    makeIpv6Type =
      _address: prefixLength:
      let
        address = toStringFromExpandedIp _address;
        addressCidr = "${address}/${toString prefixLength}";
        # RFC 2732 section-2:
        # > To use a literal IPv6 address in a URL, the literal address should be
        # > enclosed in "[" and "]" characters.
        url = "[${address}]";
        urlWithPort = port: "${url}:${toString port}";
      in
      {
        inherit
          address
          addressCidr
          prefixLength
          url
          urlWithPort
          _address
          ;
      };

    /**
      Extract an address and subnet prefix length from a string. The subnet
      prefix length is optional and defaults to 128. The resulting address and
      prefix length are validated and converted to an internal representation
      that can be used by other functions.

      # Type: string -> [ {address :: ipv6IR, prefixLength :: int} ]

      # Example:

      ```nix
      split "2001:DB8::ffff/32"
      => {
        address = [8193 3512 0 0 0 0 0 65535];
        prefixLength = 32;
      }
      ```
    */
    split =
      addr:
      let
        splitted = strings.splitString "/" addr;
        splittedLength = length splitted;
      in
      if splittedLength == 1 then # [ ip ]
        {
          address = parseIpv6FromString addr;
          prefixLength = ipv6Bits;
        }
      else if splittedLength == 2 then # [ ip subnet ]
        {
          address = parseIpv6FromString (head splitted);
          prefixLength =
            let
              n = strings.toInt (lists.last splitted);
            in
            if 1 <= n && n <= ipv6Bits then
              n
            else
              throw "${addr} IPv6 subnet should be in range [1;${toString ipv6Bits}], got ${toString n}";
        }
      else
        throw "${addr} is not a valid IPv6 address in CIDR notation";
  };
}
