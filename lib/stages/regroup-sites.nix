{ lib, splitSiteKey }:

compiledFlat:

let
  keys = lib.sort builtins.lessThan (builtins.attrNames compiledFlat);

  addOne =
    acc: k:
    let
      parts = splitSiteKey k;
      ent = parts.enterprise;
      sname = parts.siteName;

      ent0 = acc.${ent} or { };
      siteVal = compiledFlat.${k};
    in
    acc
    // {
      "${ent}" = ent0 // {
        "${sname}" = siteVal;
      };
    };
in
builtins.foldl' addOne { } keys
