{ lib }:

let
  err = import ../error.nix { inherit lib; };

  throwError = err.throwError;

  ensure = cond: msgOrErr: if cond then true else throwError msgOrErr;

  assertUnique =
    what: names:
    let
      sorted = lib.sort builtins.lessThan names;

      check =
        prev: rest:
        if rest == [ ] then
          true
        else
          let
            cur = builtins.head rest;
          in
          if prev == cur then
            throwError {
              code = "E_DUPLICATE";
              site = null;
              path = [ what ];
              message = "duplicate ${what} '${cur}'";
              hints = [
                "Ensure '${cur}' is only defined once."
                "If this name is generated, ensure the generator is deterministic and collision-free."
              ];
            }
          else
            check cur (builtins.tail rest);
    in
    if sorted == [ ] then true else check (builtins.head sorted) (builtins.tail sorted);
in
{
  inherit ensure assertUnique throwError;
}
