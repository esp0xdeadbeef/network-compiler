{ lib }:

let
  util = import ./util.nix { inherit lib; };
  inherit (util) ensure assertUnique;

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

  validateTopology =
    siteKey: topo:
    let
      nodes = topo.nodes or { };
      nodeNames = builtins.attrNames nodes;

      _uniqNodes = assertUnique "node name" nodeNames;

      roles = map (n: nodes.${n}.role or null) nodeNames;

      _hasCore = ensure (builtins.elem "core" roles) {
        code = "E_TOPO_MISSING_CORE";
        site = siteKey;
      };

      _hasPolicy = ensure (builtins.elem "policy" roles) {
        code = "E_TOPO_MISSING_POLICY";
        site = siteKey;
      };

      _hasAccess = ensure (builtins.elem "access" roles) {
        code = "E_TOPO_MISSING_ACCESS";
        site = siteKey;
      };

      links = topo.links or [ ];

      checkLink =
        pair:
        let
          _len = ensure (builtins.length pair == 2) {
            code = "E_TOPO_LINK_SHAPE";
            site = siteKey;
          };

          a = builtins.elemAt pair 0;
          b = builtins.elemAt pair 1;

          _a = ensure (builtins.elem a nodeNames) {
            code = "E_TOPO_UNKNOWN_NODE";
            site = siteKey;
          };

          _b = ensure (builtins.elem b nodeNames) {
            code = "E_TOPO_UNKNOWN_NODE";
            site = siteKey;
          };
        in
        true;

      _linksOk = builtins.foldl' (acc: pair: acc && (checkLink pair)) true links;

      touched = lib.unique (
        lib.concatMap (pair: [
          (builtins.elemAt pair 0)
          (builtins.elemAt pair 1)
        ]) links
      );

      _noIsolated = builtins.foldl' (
        acc: n:
        acc
        && ensure (builtins.elem n touched) {
          code = "E_TOPO_DISCONNECTED";
          site = siteKey;
        }
      ) true nodeNames;

      neigh = neighborsMap nodeNames links;

      start = if nodeNames == [ ] then null else builtins.elemAt (lib.sort builtins.lessThan nodeNames) 0;

      seen = if start == null then [ ] else bfs neigh start;

      _connected = ensure (builtins.length seen == builtins.length nodeNames) {
        code = "E_TOPO_DISCONNECTED";
        site = siteKey;
      };

      _force = builtins.deepSeq {
        inherit
          _uniqNodes
          _hasCore
          _hasPolicy
          _hasAccess
          _linksOk
          _noIsolated
          _connected
          ;
      } true;
    in
    builtins.seq _force true;
in
{
  inherit validateTopology;
}
