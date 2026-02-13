{ lib }:

let
  eval = import ../lib/eval.nix { inherit lib; };

  negative = import ./cases/negative.nix { inherit lib; };

  run =
    name: topo:
    let
      r = builtins.tryEval (eval {
        topology = topo;
      });
    in
    {
      inherit name;
      success = r.success;
    };

  results = map (n: run n negative.${n}) (lib.attrNames negative);

  failed = lib.filter (r: r.success) results;

in
if failed != [ ] then
  throw "Negative tests unexpectedly succeeded: ${lib.concatStringsSep ", " (map (r: r.name) failed)}"
else
  "OK"
