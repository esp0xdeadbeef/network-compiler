{ lib }:

let
  assert_ = cond: msg: if cond then true else throw msg;

  isV4 = cidr: lib.hasInfix "." cidr;

  splitCidr =
    cidr:
    let
      parts = lib.splitString "/" cidr;
    in
    if builtins.length parts != 2 then
      throw "invariants(global-user-space): invalid CIDR '${cidr}'"
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
    if n < 0 || n > 255 then throw "invariants(global-user-space): bad IPv4 octet '${s}'" else n;

  parseV4 =
    s:
    let
      p = lib.splitString "." s;
    in
    if builtins.length p != 4 then
      throw "invariants(global-user-space): bad IPv4 '${s}'"
    else
      map parseOctet p;

  v4ToInt =
    o:
    (((builtins.elemAt o 0) * 256 + (builtins.elemAt o 1)) * 256 + (builtins.elemAt o 2)) * 256
    + (builtins.elemAt o 3);

  pow2 = n: if n <= 0 then 1 else 2 * pow2 (n - 1);

  v4Range =
    cidr:
    let
      c = splitCidr cidr;
      base = v4ToInt (parseV4 c.ip);
      size = pow2 (32 - c.prefix);
    in
    {
      start = base;
      end = base + size - 1;
      cidr = cidr;
      prefix = c.prefix;
    };

  overlaps = a: b: !(a.end < b.start || b.end < a.start);

in
{
  check =
    { sites }:

    let
      siteNames = builtins.attrNames sites;

      entries = lib.concatMap (
        siteName:
        let
          site = sites.${siteName};
          nodes = site.nodes or { };
        in
        lib.concatMap (
          nodeName:
          let
            n = nodes.${nodeName};
            nets = n.networks or null;
          in
          if nets == null then
            [ ]
          else
            lib.flatten [
              (lib.optional (nets ? ipv4) {
                cidr = toString nets.ipv4;
                owner = "${siteName}: node '${nodeName}' ipv4";
              })
              (lib.optional (nets ? ipv6) {
                cidr = toString nets.ipv6;
                owner = "${siteName}: node '${nodeName}' ipv6";
              })
            ]
        ) (builtins.attrNames nodes)
      ) siteNames;

      v4Entries = lib.filter (e: isV4 e.cidr) entries;
      v6Entries = lib.filter (e: !(isV4 e.cidr)) entries;

      v4WithRanges = map (e: e // { range = v4Range e.cidr; }) v4Entries;

      v4Pairs = lib.concatMap (
        i:
        let
          a = builtins.elemAt v4WithRanges i;
        in
        map (
          j:
          let
            b = builtins.elemAt v4WithRanges j;
          in
          {
            inherit a b;
          }
        ) (lib.range (i + 1) (builtins.length v4WithRanges - 1))
      ) (lib.range 0 (builtins.length v4WithRanges - 2));

      _v4Check = lib.all (
        p:
        assert_ (!(overlaps p.a.range p.b.range)) ''
          invariants(global-user-space):

          overlapping IPv4 prefixes detected:

            ${p.a.cidr}  (${p.a.owner})
            ${p.b.cidr}  (${p.b.owner})
        ''
      ) v4Pairs;

      _v6State = builtins.foldl' (
        acc: e:
        let
          k = e.cidr;
        in
        if acc.seen ? "${k}" then
          throw ''
            invariants(global-user-space):

            duplicate IPv6 prefix detected across sites:

              ${k}

            first seen in:
              ${acc.seen.${k}}

            duplicated in:
              ${e.owner}
          ''
        else
          {
            seen = acc.seen // {
              "${k}" = e.owner;
            };
          }
      ) { seen = { }; } v6Entries;

    in
    builtins.seq _v4Check (builtins.seq _v6State true);

}
