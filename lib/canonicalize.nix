{ lib }:

let
  sortedKeys = a: lib.sort builtins.lessThan (builtins.attrNames a);

  go =
    v:
    if builtins.isAttrs v then
      builtins.listToAttrs (
        map (k: {
          name = k;
          value = go v.${k};
        }) (sortedKeys v)
      )
    else if builtins.isList v then
      map go v
    else
      v;
in
go
