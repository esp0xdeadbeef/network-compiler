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

  universeCidr = if builtins.isAttrs args && args ? universe then args.universe else "0.0.0.0/0";

  pow2 = n: lib.foldl' (acc: _: acc * 2) 1 (builtins.genList (_: null) n);

  parseOctet =
    s:
    let
      n = lib.toInt s;
    in
    if n < 0 || n > 255 then throw "cidr-substract(v4): bad IPv4 octet '${s}'" else n;

  parseIp4 =
    s:
    let
      parts = lib.splitString "." s;
    in
    if builtins.length parts != 4 then
      throw "cidr-substract(v4): bad IPv4 address '${s}'"
    else
      map parseOctet parts;

  parseCidr4 =
    s:
    if !(builtins.isString s && lib.hasInfix "." s) then
      throw "cidr-substract(v4): expected IPv4 CIDR string, got: ${builtins.toString s}"
    else
      let
        parts = lib.splitString "/" s;
        ipStr = builtins.elemAt parts 0;
        len = if builtins.length parts == 2 then lib.toInt (builtins.elemAt parts 1) else 32;
      in
      if len < 0 || len > 32 then
        throw "cidr-substract(v4): bad prefix length in '${s}'"
      else
        {
          inherit len;
          segs = parseIp4 ipStr;
        };

  canonicalize4 =
    c:
    let
      len = c.len;
      full = builtins.div len 8;
      rem = len - (full * 8);

      mask = if rem == 0 then 0 else (pow2 rem - 1) * (pow2 (8 - rem));

      segs = c.segs;
      out = builtins.genList (
        i:
        if i < full then
          builtins.elemAt segs i
        else if i == full && rem != 0 then
          builtins.bitAnd (builtins.elemAt segs i) mask
        else
          0
      ) 4;
    in
    {
      inherit (c) len;
      segs = out;
    };

  maskToLen4 =
    c: l:
    canonicalize4 {
      len = l;
      segs = c.segs;
    };

  contains4 =
    super: sub: (sub.len >= super.len) && (canonicalize4 super).segs == (maskToLen4 sub super.len).segs;

  setBit4 =
    segs: bitIndex:
    let
      segIdx = builtins.div bitIndex 8;
      bitInSeg = bitIndex - (segIdx * 8);
      mask = pow2 (7 - bitInSeg);

      old = builtins.elemAt segs segIdx;
      new = builtins.bitOr old mask;
    in
    builtins.genList (i: if i == segIdx then new else builtins.elemAt segs i) 4;

  split4 =
    c:
    let
      c' = canonicalize4 c;
    in
    if c'.len >= 32 then
      throw "cidr-substract(v4): cannot split /32"
    else
      let
        newLen = c'.len + 1;
        left = canonicalize4 {
          len = newLen;
          segs = c'.segs;
        };
        right = canonicalize4 {
          len = newLen;
          segs = setBit4 c'.segs c'.len;
        };
      in
      [
        left
        right
      ];

  toString4 =
    c:
    let
      ip = lib.concatStringsSep "." (map toString c.segs);
    in
    "${ip}/${toString c.len}";

  subtractPrefix4 =
    p: b:
    let
      p' = canonicalize4 p;
      b' = canonicalize4 b;
    in
    if contains4 b' p' then
      [ ]
    else if contains4 p' b' then
      if p'.len == b'.len then
        [ ]
      else
        let
          halves = split4 p';
          left = builtins.elemAt halves 0;
          right = builtins.elemAt halves 1;
        in
        if contains4 left b' then
          (subtractPrefix4 left b') ++ [ right ]
        else if contains4 right b' then
          (subtractPrefix4 right b') ++ [ left ]
        else

          [
            left
            right
          ]
    else
      [ p' ];

  subtractOne4 = acc: block: lib.flatten (map (p: subtractPrefix4 p block) acc);

  blockedObjs = map parseCidr4 (
    lib.unique (lib.filter (s: builtins.isString s && lib.hasInfix "/" s) blockedCidrs)
  );

  universeObj = canonicalize4 (parseCidr4 universeCidr);

  resultObjs = lib.foldl' subtractOne4 [ universeObj ] blockedObjs;
in
map toString4 resultObjs
