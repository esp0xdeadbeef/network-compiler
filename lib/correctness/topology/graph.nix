{ lib }:

let
  normalizeLinkPair =
    pair:
    let
      a = builtins.elemAt pair 0;
      b = builtins.elemAt pair 1;
    in
    lib.sort builtins.lessThan [
      a
      b
    ];

  neighborsMap =
    nodeNames: links:
    let
      empty = lib.genAttrs nodeNames (_: [ ]);

      addEdge =
        acc: pair:
        let
          a = builtins.elemAt pair 0;
          b = builtins.elemAt pair 1;
        in
        acc
        // {
          "${a}" = (acc.${a} or [ ]) ++ [ b ];
          "${b}" = (acc.${b} or [ ]) ++ [ a ];
        };
    in
    builtins.foldl' addEdge empty links;

  bfs =
    neigh: start:
    let
      step =
        state: _:
        let
          queue = state.queue;
        in
        if queue == [ ] then
          state
        else
          let
            cur = builtins.head queue;
            rest = builtins.tail queue;

            ns = neigh.${cur} or [ ];
            unseen = lib.filter (n: !(builtins.elem n state.seen)) ns;

            seen' = state.seen ++ unseen;
            queue' = rest ++ unseen;
          in
          {
            seen = seen';
            queue = queue';
          };

      nodeCount = builtins.length (builtins.attrNames neigh);
      state0 = {
        seen = [ start ];
        queue = [ start ];
      };

      stateN = builtins.foldl' step state0 (lib.range 1 (nodeCount + 1));
    in
    stateN.seen;
in
{
  inherit normalizeLinkPair neighborsMap bfs;
}
