{ lib }:

let
  discovered =
    if builtins.pathExists ./routing-validation then builtins.readDir ./routing-validation else { };

  suite = builtins.map (name: ./routing-validation + "/${name}") (
    lib.filter (
      name:
      let
        t = discovered.${name};
      in
      t == "regular" && lib.hasSuffix ".nix" name
    ) (builtins.attrNames discovered)
  );

  results = builtins.map (
    path:
    let
      attempt = builtins.tryEval (import path { inherit lib; });

      ok =
        if attempt.success then
          let
            value = attempt.value;
          in
          if builtins.isAttrs value && value ? ok then
            value.ok
          else if builtins.isBool value then
            value
          else
            false
        else
          false;
    in
    {
      name = builtins.baseNameOf path;
      inherit ok;
    }
  ) suite;

  failures = lib.filter (r: if r ? ok then r.ok != true else true) results;

in
if failures != [ ] then
  throw ''
    ROUTING VALIDATION TESTS FAILED

    ${lib.concatStringsSep "\n" (builtins.map (r: r.name) failures)}
  ''
else
  "ROUTING VALIDATION TESTS OK"
