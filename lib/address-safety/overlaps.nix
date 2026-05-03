{ lib, throwError }:

let
  overlaps = a: b: !(a.end < b.start || b.end < a.start);

  assertNoOverlaps =
    what: ranges:
    let
      sorted = lib.sort (a: b: a.start < b.start) ranges;

      check =
        prev: rest:
        if rest == [ ] then
          true
        else
          let
            cur = builtins.head rest;
          in
          if overlaps prev cur then
            throwError {
              code = "E_ADDR_OVERLAP";
              site = null;
              path = [ "address" ];
              message = "overlapping ${what}: '${prev.raw}' and '${cur.raw}'";
              hints = [ "Ensure CIDRs do not overlap." ];
            }
          else
            check cur (builtins.tail rest);
    in
    if sorted == [ ] then true else check (builtins.head sorted) (builtins.tail sorted);

  assertNoCrossOverlaps =
    what: left: right:
    let
      checkOne =
        a:
        map (
          b:
          if overlaps a b then
            throwError {
              code = "E_ADDR_OVERLAP";
              site = null;
              path = [ "address" ];
              message = "overlapping ${what}: '${a.raw}' and '${b.raw}'";
              hints = [ "Separate pool ranges from tenant prefixes." ];
            }
          else
            true
        ) right;
    in
    map checkOne left;
in
{
  inherit assertNoOverlaps assertNoCrossOverlaps;
}
