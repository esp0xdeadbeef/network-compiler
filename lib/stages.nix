{ lib }:

let
  normalizeSite = import ./normalize/from-user-input.nix { inherit lib; };
  compileSite = import ./compile-site.nix { inherit lib; };
  invariants = import ./fabric/invariants/default.nix { inherit lib; };

  assert_ = cond: msg: if cond then true else throw msg;

  isSite = v: builtins.isAttrs v && (v ? nodes || v ? links || v ? p2p-pool);

  isCompiledSite = v: builtins.isAttrs v && v ? nodes && v ? links && builtins.isAttrs v.links;

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
            ) "stages.flatten: enterprise '${name}' must contain at least one site";
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
                throw "stages.flatten: enterprise '${name}' contains non-site attribute '${sname}'";
          in
          builtins.foldl' addSite acc siteNames
        else
          throw "stages.flatten: top-level attribute '${name}' must be a site or enterprise attrset";
    in
    builtins.foldl' addOne { } topNames;

  normalizeAll = sites: lib.mapAttrs (_: s: normalizeSite s) sites;

  checkSiteAll =
    sites: builtins.deepSeq (lib.mapAttrs (_: s: invariants.checkSite { site = s; }) sites) true;

  checkAllGlobal = sites: builtins.deepSeq (invariants.checkAll { inherit sites; }) true;

  runPreInvariants =
    sites: builtins.seq (checkSiteAll sites) (builtins.seq (checkAllGlobal sites) sites);

  compileAll = sites: lib.mapAttrs (_: s: if isCompiledSite s then s else compileSite s) sites;

  runPostInvariants = compiled: builtins.seq (checkSiteAll compiled) compiled;

in
{
  flatten = inputs: flattenSites inputs;

  normalize = inputs: normalizeAll (flattenSites inputs);

  "invariants-pre" = inputs: runPreInvariants (normalizeAll (flattenSites inputs));

  compile = inputs: compileAll (runPreInvariants (normalizeAll (flattenSites inputs)));

  "invariants-post" =
    inputs: runPostInvariants (compileAll (runPreInvariants (normalizeAll (flattenSites inputs))));

  checkSites = sites: builtins.seq (checkSiteAll sites) (builtins.seq (checkAllGlobal sites) true);
}
