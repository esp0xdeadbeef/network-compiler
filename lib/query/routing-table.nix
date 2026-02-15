# ./lib/query/routing-table.nix
{ lib }:

routed:

let
  membersOf =
    l:
    lib.unique ((l.members or [ ]) ++ (builtins.attrNames (l.endpoints or { })));

  mk =
    node:
    let
      links = lib.filterAttrs (_: l: lib.elem node (membersOf l)) (routed.links or { });

      eps = lib.concatMap (
        l:
        let
          ep = (l.endpoints or { }).${node} or { };
        in
        (ep.routes4 or [ ]) ++ (ep.routes6 or [ ])
      ) (lib.attrValues links);
    in
    eps;

in
lib.listToAttrs (
  map (n: {
    name = n;
    value = mk n;
  }) (lib.attrNames (routed.nodes or { }))
)

