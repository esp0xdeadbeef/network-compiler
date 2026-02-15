{ lib }:

topo:

let
  links = topo.links or { };

  isWan = l: (l.kind or null) == "wan";

  getEp = l: n: (l.endpoints or { }).${n} or { };

  setEp =
    l: n: ep:
    l
    // {
      endpoints = (l.endpoints or { }) // {
        "${n}" = ep;
      };
    };

  asList = x: if x == null then [ ] else x;

  hasDefault4 = rs: lib.any (r: (r.dst or null) == "0.0.0.0/0") (asList rs);
  hasDefault6 = rs: lib.any (r: (r.dst or null) == "::/0") (asList rs);

  normalize4 =
    ep:
    let
      dhcp = ep.dhcp or false;
      rs0 = asList (ep.routes4 or [ ]);
      rs1 = map (
        r: if (r.dst or null) == "0.0.0.0/0" && !(r ? via4) && dhcp then r // { via4 = "_dhcp4"; } else r
      ) rs0;

      add =
        if dhcp && !(hasDefault4 rs1) then
          [
            {
              dst = "0.0.0.0/0";
              via4 = "_dhcp4";
            }
          ]
        else
          [ ];
    in
    rs1 ++ add;

  normalize6 =
    ep:
    let
      dhcp = ep.dhcp or false;
      ra = ep.acceptRA or false;

      rs0 = asList (ep.routes6 or [ ]);
      rs1 = map (
        r:
        if (r.dst or null) == "::/0" && !(r ? via6) then
          if ra then
            r // { via6 = "_ipv6ra"; }
          else if dhcp then
            r // { via6 = "_dhcp6"; }
          else
            r
        else
          r
      ) rs0;

      add =
        if ra && !(hasDefault6 rs1) then
          [
            {
              dst = "::/0";
              via6 = "_ipv6ra";
            }
          ]
        else if dhcp && !(hasDefault6 rs1) then
          [
            {
              dst = "::/0";
              via6 = "_dhcp6";
            }
          ]
        else
          [ ];
    in
    rs1 ++ add;

in
topo
// {
  links = lib.mapAttrs (
    _lname: l:
    if !isWan l then
      l
    else
      lib.foldl' (
        acc: node:
        let
          ep0 = getEp acc node;
          ep = ep0 // {
            routes4 = normalize4 ep0;
            routes6 = normalize6 ep0;
          };
        in
        setEp acc node ep
      ) l (builtins.attrNames (l.endpoints or { }))
  ) links;
}
