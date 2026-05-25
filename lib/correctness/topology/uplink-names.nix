{ lib }:

let
  util = import ../util.nix { inherit lib; };
  inherit (util) assertUnique throwError;
in
{
  assertUniqueSiteUplinkNames =
    siteKey: names:
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
            throwError
              {
                code = "E_UPLINK_NAME_NOT_UNIQUE";
                site = siteKey;
                path = [
                  "topology"
                  "nodes"
                ];
                message = "uplink name '${cur}' must be unique across all core nodes in the site";
                hints = [
                  "Rename one of the duplicate uplinks so external names stay unambiguous."
                  "Using 'wan' is fine when it appears only once in the site."
                ];
              }
          else
            check cur (builtins.tail rest);
    in
    if sorted == [ ] then true else check (builtins.head sorted) (builtins.tail sorted);

  inherit assertUnique;
}
