{ lib }:

inputs:

let
  assert_ = cond: msg: if cond then true else throw msg;

  isSite = v: builtins.isAttrs v && (v ? nodes || v ? links || v ? p2p-pool);

  flattenSites =
    top:
    let
      topNames = builtins.attrNames top;

      addOne =
        acc: name:
        let
          v = top.${name};
        in
        if isSite v then
          acc // { "${name}" = v; }
        else if builtins.isAttrs v then
          let
            siteNames = builtins.attrNames v;

            _nonEmpty = assert_ (
              siteNames != [ ]
            ) "from-inputs: enterprise '${name}' must contain at least one site";

            addSite =
              acc2: sname:
              let
                sv = v.${sname};
              in
              if isSite sv then
                acc2
                // {
                  "${name}.${sname}" = sv // {
                    enterprise = name;
                    siteName = sname;
                  };
                }
              else
                throw "from-inputs: enterprise '${name}' contains non-site attribute '${sname}'";
          in
          builtins.foldl' addSite acc siteNames
        else
          throw "from-inputs: top-level attribute '${name}' must be a site or an enterprise attrset";
    in
    builtins.foldl' addOne { } topNames;

  sites = flattenSites inputs;

  normalizeSite = import ./normalize/from-user-input.nix { inherit lib; };
  compileSite = import ./compile-site.nix { inherit lib; };

  normalizedSites = lib.mapAttrs (_: site: normalizeSite site) sites;
  compiledSites = lib.mapAttrs (_: site: compileSite site) normalizedSites;

in
compiledSites
