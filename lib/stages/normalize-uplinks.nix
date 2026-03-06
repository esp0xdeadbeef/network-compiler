{ lib }:

siteKey: nodeName: u:

if u == null then
  [ ]
else if builtins.isAttrs u then
  let
    names = lib.sort builtins.lessThan (builtins.attrNames u);
  in
  map (
    name:
    let
      v = u.${name};
    in
    v
    // {
      inherit name;
      ipv4 = v.ipv4 or [ ];
      ipv6 = v.ipv6 or [ ];
      ingressSubject = v.ingressSubject or null;
    }
  ) names
else
  [ ]
