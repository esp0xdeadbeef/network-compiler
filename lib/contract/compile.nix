{ lib }:

let
  invariantsMod = import ../fabric/invariants { inherit lib; };

  runInvariants =
    site:
    let
      tryCheck =
        if invariantsMod ? check then
          invariantsMod.check
        else if invariantsMod ? run then
          invariantsMod.run
        else if invariantsMod ? validate then
          invariantsMod.validate
        else
          null;

      _ = if tryCheck == null then true else tryCheck { inherit site; };
    in
    true;

  normalizeSite =
    siteName: site:
    let
      site' =
        if builtins.isAttrs site then
          site // { inherit siteName; }
        else
          throw "compileContract: site '${siteName}' is not an attribute set";

      _ = runInvariants site';
    in
    site';

  normalizeInput =
    input:
    let
      v =
        if lib.hasSuffix ".json" input then builtins.fromJSON (builtins.readFile input) else import input;
    in
    if builtins.isAttrs v then
      v
    else
      throw "compileContract: '${toString input}' must evaluate to an attribute set of sites";
in
{ input }:
let
  sites = normalizeInput input;
  compiled = lib.mapAttrs normalizeSite sites;
in
compiled
