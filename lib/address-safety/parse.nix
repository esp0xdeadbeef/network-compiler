{ lib, ensure, throwError }:

let
  parseIPv4 =
    cidr:
    let
      parts = lib.splitString "/" cidr;
      _len = ensure (builtins.length parts == 2) {
        code = "E_ADDR_INVALID_CIDR";
        site = null;
        path = [
          "ownership"
          "prefixes"
        ];
        message = "invalid IPv4 CIDR '${toString cidr}'";
        hints = [ "Use a.b.c.d/prefix." ];
      };

      base = builtins.elemAt parts 0;
      prefix = lib.toInt (builtins.elemAt parts 1);

      octets = lib.splitString "." base;
      _octLen = ensure (builtins.length octets == 4) {
        code = "E_ADDR_INVALID_IPV4";
        site = null;
        path = [
          "ownership"
          "prefixes"
        ];
        message = "invalid IPv4 address '${base}'";
        hints = [ "Use four octets a.b.c.d." ];
      };

      toOctet =
        s:
        let
          v = lib.toInt s;
        in
        if 0 <= v && v <= 255 then
          v
        else
          throwError {
            code = "E_ADDR_INVALID_IPV4";
            site = null;
            path = [
              "ownership"
              "prefixes"
            ];
            message = "IPv4 octet out of range in '${base}'";
            hints = [ "Each octet must be 0..255." ];
          };

      o0 = toOctet (builtins.elemAt octets 0);
      o1 = toOctet (builtins.elemAt octets 1);
      o2 = toOctet (builtins.elemAt octets 2);
      o3 = toOctet (builtins.elemAt octets 3);

      _pref = ensure (0 <= prefix && prefix <= 32) {
        code = "E_ADDR_INVALID_PREFIX";
        site = null;
        path = [
          "ownership"
          "prefixes"
        ];
        message = "IPv4 prefix must be in [0..32] in '${cidr}'";
        hints = [ "Use /0..../32." ];
      };

      baseInt = (((o0 * 256) + o1) * 256 + o2) * 256 + o3;
      size = builtins.foldl' (acc: _: acc * 2) 1 (lib.range 1 (32 - prefix));
      start = baseInt;
      end = baseInt + size - 1;
    in
    {
      inherit start end prefix;
      version = 4;
      raw = cidr;
    };

  parseIPv6 =
    cidr:
    let
      parsed = lib.network.ipv6.fromString cidr;

      first = lib.network.ipv6.firstAddress parsed;
      last = lib.network.ipv6.lastAddress parsed;

      toInt = a: builtins.foldl' (acc: part: acc * 65536 + part) 0 a.address;

      start = toInt first;
      end = toInt last;
    in
    {
      inherit start end;
      version = 6;
      raw = cidr;
    };

  parseAny = cidr: if lib.hasInfix ":" cidr then parseIPv6 cidr else parseIPv4 cidr;
in
{
  inherit parseAny;
}
