{ lib }:

inputs:

let
  util = import ./correctness/util.nix { inherit lib; };
  inherit (util) ensure throwError;

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

  sortedAttrNames = a: lib.sort builtins.lessThan (builtins.attrNames a);

  flattenSites =
    top:
    let
      topNames = sortedAttrNames top;

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
            siteNames = sortedAttrNames v;

            _nonEmpty = ensure (siteNames != [ ]) {
              code = "E_INPUT_EMPTY_ENTERPRISE";
              site = null;
              path = [ name ];
              message = "enterprise '${name}' must contain at least one site";
              hints = [ "Add at least one site attribute under '${name}'." ];
            };

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
                throwError {
                  code = "E_INPUT_NON_SITE";
                  site = null;
                  path = [
                    name
                    sname
                  ];
                  message = "enterprise '${name}' contains non-site attribute '${sname}'";
                  hints = [
                    "Sites must be new-style: { topology = { nodes = ...; links = ...; }; ... }"
                    "Move non-site data elsewhere or nest sites one level deeper."
                  ];
                };
          in
          builtins.foldl' addSite acc siteNames
        else
          throwError {
            code = "E_INPUT_TOPLEVEL_SHAPE";
            site = null;
            path = [ name ];
            message = "top-level attribute '${name}' must be a site or an enterprise attrset";
            hints = [ "Provide a site definition or an attribute set of sites." ];
          };
    in
    builtins.foldl' addOne { } topNames;

in
flattenSites inputs
