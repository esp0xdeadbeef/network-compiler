{ lib }:

args:

let
  blockedCidrs =
    if builtins.isList args then
      args
    else if builtins.isAttrs args && args ? blockedCidrs then
      args.blockedCidrs
    else
      args;

  universeCidr = if builtins.isAttrs args && args ? universe then args.universe else "::/0";

  isCidr = s: builtins.isString s && lib.hasInfix "/" s && lib.hasInfix ":" s;

  pow2 = n: lib.foldl' (acc: _: acc * 2) 1 (builtins.genList (_: null) n);

  hexToInt = s: if s == "" then 0 else (builtins.fromTOML "x = 0x${s}").x;

  parseHextet =
    s:
    let
      n = hexToInt s;
    in
    if n < 0 || n > 65535 then throw "cidr-subtract(v6): invalid hextet '${s}'" else n;

  expandIPv6 =
    s:
    let
      parts = lib.splitString "::" s;
    in
    if builtins.length parts == 1 then
      let
        hs = lib.splitString ":" s;
      in
      if builtins.length hs != 8 then
        throw "cidr-subtract(v6): invalid IPv6 address '${s}'"
      else
        map parseHextet hs
    else if builtins.length parts == 2 then
      let
        left = if builtins.elemAt parts 0 == "" then [ ] else lib.splitString ":" (builtins.elemAt parts 0);

        right =
          if builtins.elemAt parts 1 == "" then [ ] else lib.splitString ":" (builtins.elemAt parts 1);

        missing = 8 - (builtins.length left + builtins.length right);
      in
      if missing < 0 then
        throw "cidr-subtract(v6): invalid IPv6 address '${s}'"
      else
        (map parseHextet left) ++ (builtins.genList (_: 0) missing) ++ (map parseHextet right)
    else
      throw "cidr-subtract(v6): invalid IPv6 address '${s}'";

  canonicalize =
    c:
    let
      full = builtins.div c.len 16;
      rem = c.len - (full * 16);

      mask = if rem == 0 then 0 else (pow2 rem - 1) * (pow2 (16 - rem));

      segs = c.segs;

      out = builtins.genList (
        i:
        if i < full then
          builtins.elemAt segs i
        else if i == full && rem != 0 then
          builtins.bitAnd (builtins.elemAt segs i) mask
        else
          0
      ) 8;
    in
    {
      inherit (c) len;
      segs = out;
    };

  parseCidr6 =
    s:
    let
      parts = lib.splitString "/" s;
      ip = builtins.elemAt parts 0;
      len = if builtins.length parts == 2 then lib.toInt (builtins.elemAt parts 1) else 128;
    in
    if len < 0 || len > 128 then
      throw "cidr-subtract(v6): invalid prefix length in '${s}'"
    else
      canonicalize {
        inherit len;
        segs = expandIPv6 ip;
      };

  maskToLen =
    c: l:
    canonicalize {
      len = l;
      segs = c.segs;
    };

  contains =
    super: sub: (sub.len >= super.len) && (canonicalize super).segs == (maskToLen sub super.len).segs;

  setBit =
    segs: bitIndex:
    let
      segIdx = builtins.div bitIndex 16;
      bitInSeg = bitIndex - (segIdx * 16);
      mask = pow2 (15 - bitInSeg);

      old = builtins.elemAt segs segIdx;
      new = builtins.bitOr old mask;
    in
    builtins.genList (i: if i == segIdx then new else builtins.elemAt segs i) 8;

  split =
    c:
    let
      c' = canonicalize c;
    in
    if c'.len >= 128 then
      throw "cidr-subtract(v6): cannot split /128"
    else
      let
        newLen = c'.len + 1;

        left = canonicalize {
          len = newLen;
          segs = c'.segs;
        };
        right = canonicalize {
          len = newLen;
          segs = setBit c'.segs c'.len;
        };
      in
      [
        left
        right
      ];

  toHex =
    n:
    let
      digits = [
        "0"
        "1"
        "2"
        "3"
        "4"
        "5"
        "6"
        "7"
        "8"
        "9"
        "a"
        "b"
        "c"
        "d"
        "e"
        "f"
      ];

      go =
        x:
        if x < 16 then
          builtins.elemAt digits x
        else
          let
            q = builtins.div x 16;
            r = x - q * 16;
          in
          (go q) + (builtins.elemAt digits r);
    in
    go n;

  pad4 =
    s:
    let
      len = builtins.stringLength s;
      zeros = builtins.concatStringsSep "" (builtins.genList (_: "0") (lib.max 0 (4 - len)));
    in
    zeros + s;

  toString6 =
    c:
    let
      segStrs = map (x: pad4 (toHex x)) c.segs;
      ip = lib.concatStringsSep ":" segStrs;
    in
    "${ip}/${builtins.toString c.len}";

  subtractPrefix =
    p: b:
    if contains b p then
      [ ]
    else if contains p b then
      if p.len == b.len then
        [ ]
      else
        let
          halves = split p;
          left = builtins.elemAt halves 0;
          right = builtins.elemAt halves 1;
        in
        if contains left b then
          (subtractPrefix left b) ++ [ right ]
        else if contains right b then
          (subtractPrefix right b) ++ [ left ]
        else
          [
            left
            right
          ]
    else
      [ p ];

  subtractOne = acc: block: lib.flatten (map (p: subtractPrefix p block) acc);

  blockedObjs = map parseCidr6 (lib.unique (lib.filter isCidr blockedCidrs));

  universeObj = parseCidr6 universeCidr;

  resultObjs = lib.foldl' subtractOne [ universeObj ] blockedObjs;

in
map toString6 resultObjs
