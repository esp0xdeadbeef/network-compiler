{ lib }:

let
  err = import ../error.nix { inherit lib; };

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
          err.throwError {
            code = "E_CONTRACT_SITE_NOT_ATTRSET";
            site = siteName;
            path = [ siteName ];
            message = "site must be an attribute set";
            hints = [ "Ensure each site evaluates to an attribute set." ];
          };

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
      err.throwError {
        code = "E_CONTRACT_INPUT_NOT_ATTRSET";
        site = null;
        path = [ ];
        message = "'${toString input}' must evaluate to an attribute set of sites";
        hints = [
          "If using Nix, return an attrset: { site-a = { ... }; }"
          "If using JSON, the top-level must be an object mapping site keys to site configs."
        ];
      };
in
{ input }:
let
  sites = normalizeInput input;
  compiled = lib.mapAttrs normalizeSite sites;
in
compiled
