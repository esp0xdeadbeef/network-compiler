{ lib }:

inputs:

let
  assert_ = cond: msg: if cond then true else throw msg;

  isSite =
    v:
    builtins.isAttrs v
    && v ? topology
    && builtins.isAttrs v.topology
    && (v.topology ? nodes)
    && builtins.isAttrs v.topology.nodes;

  splitSiteKey =
    key:
    let
      m = builtins.match "([^.]*)\\.(.*)" key;
    in
    if m == null then
      {
        enterprise = "default";
        siteName = key;
      }
    else
      {
        enterprise = builtins.elemAt m 0;
        siteName = builtins.elemAt m 1;
      };

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
          let
            parts = splitSiteKey name;
          in
          acc
          // {
            "${name}" = v // {
              inherit (parts) enterprise siteName;
            };
          }
        else if builtins.isAttrs v then
          let
            siteNames = builtins.attrNames v;

            _nonEmpty = assert_ (siteNames != [ ]) ''
              flatten-sites: enterprise '${name}' must contain at least one site
            '';

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
                throw ''
                  flatten-sites: enterprise '${name}' contains non-site attribute '${sname}'
                  (sites must be new-style: { topology = { nodes = ...; links = ...; }; ... })
                '';
          in
          builtins.foldl' addSite acc siteNames
        else
          throw ''
            flatten-sites: top-level attribute '${name}' must be a site or an enterprise attrset
          '';
    in
    builtins.foldl' addOne { } topNames;

in
flattenSites inputs
