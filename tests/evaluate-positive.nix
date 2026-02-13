{ lib }:

let

  casesDir = ./cases;

  caseNames = lib.filter (name: lib.hasSuffix ".nix" name && name != "negative.nix") (
    builtins.attrNames (builtins.readDir casesDir)
  );

  tests = lib.genAttrs (map (n: lib.removeSuffix ".nix" n) caseNames) (
    name: import (casesDir + "/${name}.nix") { inherit lib; }
  );

  results = lib.mapAttrs (
    name: expr:
    let
      attempt = builtins.tryEval expr;
    in
    if attempt.success then
      null
    else
      builtins.trace ''
        ============================================
        POSITIVE TEST FAILED: ${name}
        ============================================
      '' name
  ) tests;

  failures = lib.filter (x: x != null) (lib.attrValues results);

in
if failures != [ ] then
  throw ''
    Positive tests FAILED (they should evaluate successfully but did not):

    - ${lib.concatStringsSep "\n    - " failures}
  ''
else
  "POSITIVE TESTS OK\n"
