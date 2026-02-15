{ lib }:

let
  discovered = if builtins.pathExists ./negative then builtins.readDir ./negative else { };

  testFiles = lib.filter (
    name:
    let
      t = discovered.${name};
    in
    t == "regular" && lib.hasSuffix ".nix" name
  ) (builtins.attrNames discovered);

  tests = builtins.map (name: {
    name = lib.removeSuffix ".nix" name;
    path = ./negative + "/${name}";
  }) testFiles;

  results = builtins.map (
    t:
    let
      attempt = builtins.tryEval (import t.path);
    in
    {
      inherit (t) name;
      success = attempt.success or false;
    }
  ) tests;

  failed = builtins.filter (r: r.success) results;

  failedNames = builtins.map (r: r.name) failed;

in
if failedNames == [ ] then
  "NEGATIVE TESTS OK"
else
  throw ''
    NEGATIVE TESTS FAILED

    The following tests unexpectedly evaluated successfully:
    ${lib.concatStringsSep "\n" failedNames}
  ''
