{ lib }:

let
  evalNetwork = import ../lib/eval.nix { inherit lib; };

  cases = import ./cases/negative.nix { inherit lib; };

  runOne =
    name: topo:
    let
      r = builtins.tryEval (evalNetwork {
        topology = topo;
      });
    in
    {
      inherit name;
      ok = !r.success;
    };

  results = map (n: runOne n cases.${n}) (lib.attrNames cases);

  failures = lib.filter (r: !r.ok) results;

in
if failures != [ ] then
  throw ''
    Negative tests FAILED (they evaluated successfully but should not):

    ${lib.concatStringsSep "\n" (map (r: " - " + r.name) failures)}
  ''
else
  "NEGATIVE TESTS OK"
