{ lib }:

let

  splitCidr =
    cidr:
    let
      parts = lib.splitString "/" cidr;
    in
    if builtins.length parts != 2 then
      throw "p2p.alloc: invalid CIDR '${cidr}'"
    else
      {
        ip = builtins.elemAt parts 0;
        prefix = lib.toInt (builtins.elemAt parts 1);
      };

  parseOctet =
    s:
    let
      n = lib.toInt s;
    in
    if n < 0 || n > 255 then throw "p2p.alloc: bad IPv4 octet '${s}'" else n;

  parseV4 =
    s:
    let
      p = lib.splitString "." s;
    in
    if builtins.length p != 4 then throw "p2p.alloc: bad IPv4 '${s}'" else map parseOctet p;

  v4ToInt =
    o:
    (((builtins.elemAt o 0) * 256 + (builtins.elemAt o 1)) * 256 + (builtins.elemAt o 2)) * 256
    + (builtins.elemAt o 3);

  intToV4 =
    n:
    let
      o0 = builtins.div n (256 * 256 * 256);
      r0 = n - o0 * (256 * 256 * 256);
      o1 = builtins.div r0 (256 * 256);
      r1 = r0 - o1 * (256 * 256);
      o2 = builtins.div r1 256;
      o3 = r1 - o2 * 256;
    in
    lib.concatStringsSep "." (
      map toString [
        o0
        o1
        o2
        o3
      ]
    );

  nextV4 =
    ip: inc:
    let
      base = v4ToInt (parseV4 ip);
    in
    intToV4 (base + inc);

  ipv6 = lib.network.ipv6;

  hexToInt = s: if s == "" then 0 else (builtins.fromTOML "x = 0x${s}").x;
  toHex = n: lib.toHexString n;

  parseHextet =
    s:
    let
      n = hexToInt s;
    in
    if n < 0 || n > 65535 then throw "p2p.alloc: bad IPv6 hextet '${s}'" else n;

  parseV6Expanded = s: map parseHextet (lib.splitString ":" s);

  addV6 =
    segs: inc:
    let
      addRec =
        i: carry: acc:
        if i < 0 then
          acc
        else
          let
            sum = (builtins.elemAt segs i) + carry;
            newVal = sum - (builtins.div sum 65536) * 65536;
            newCarry = builtins.div sum 65536;
          in
          addRec (i - 1) newCarry ([ newVal ] ++ acc);
    in
    addRec 7 inc [ ];

  v6ToStr = segs: lib.concatStringsSep ":" (map toHex segs);

  nextV6 =
    ip: inc:
    let
      parsed = ipv6.fromString ip;
      segs0 = parseV6Expanded parsed.address;
      segs1 = addV6 segs0 inc;
    in
    v6ToStr segs1;

  normPair =
    pair:
    let
      a0 = builtins.elemAt pair 0;
      b0 = builtins.elemAt pair 1;
    in
    if a0 < b0 then
      {
        a = a0;
        b = b0;
      }
    else
      {
        a = b0;
        b = a0;
      };

  pairKey = p: "${p.a}|${p.b}";

in
{

  alloc =
    { p2p, links }:
    let
      v4 = splitCidr p2p.ipv4;
      v6 = splitCidr p2p.ipv6;

      ps0 = map normPair links;
      ps = lib.sort (x: y: pairKey x < pairKey y) ps0;

      mkOne =
        i: p:
        let
          offA = 2 * i;
          offB = offA + 1;

          addr4A = "${nextV4 v4.ip offA}/31";
          addr4B = "${nextV4 v4.ip offB}/31";

          addr6A = "${nextV6 v6.ip offA}/127";
          addr6B = "${nextV6 v6.ip offB}/127";

          linkName = "p2p-${p.a}-${p.b}";
        in
        {
          name = linkName;
          value = {
            kind = "p2p";
            endpoints = {
              "${p.a}" = {
                addr4 = addr4A;
                addr6 = addr6A;
              };
              "${p.b}" = {
                addr4 = addr4B;
                addr6 = addr6B;
              };
            };
          };
        };

    in
    lib.listToAttrs (lib.imap0 mkOne ps);
}
