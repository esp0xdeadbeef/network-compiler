{ lib }:

let
  util = import ../util.nix { inherit lib; };
  inherit (util) ensure;

  # BFS path-finder: returns the path from start to end (including both
  # endpoints), or null if unreachable.
  findPath =
    neigh: start: end:
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
            headItem = builtins.head queue;
            current = builtins.elemAt headItem 0;
            currentPath = builtins.elemAt headItem 1;
            rest = builtins.tail queue;
          in
          if current == end then
            {
              seen = state.seen;
              queue = [ ];
              found = currentPath;
            }
          else
            let
              ns = neigh.${current} or [ ];
              unseen = lib.filter (n: !(builtins.elem n state.seen)) ns;
              seen' = state.seen ++ unseen;
              newEntries = map (n: [
                n
                (currentPath ++ [ n ])
              ]) unseen;
              queue' = rest ++ newEntries;
            in
            {
              seen = seen';
              queue = queue';
              found = null;
            };

      nodeCount = builtins.length (builtins.attrNames neigh);
      state0 = {
        seen = [ start ];
        queue = [ [ start [ start ] ] ];
        found = null;
      };
      stateN = builtins.foldl' step state0 (lib.range 1 (nodeCount + 1));
    in
    stateN.found;

  pathContainsPolicy =
    nodes: path:
    builtins.any (n: (nodes.${n}.role or null) == "policy") path;

  validatePolicyTraversal =
    siteKey: nodes: links:
    let
      nodeNames = builtins.attrNames nodes;
      neigh = (import ./graph.nix { inherit lib; }).neighborsMap nodeNames links;

      checkPair =
        acc: pair:
        let
          a = builtins.elemAt pair 0;
          b = builtins.elemAt pair 1;
          roleA = nodes.${a}.role or null;
          roleB = nodes.${b}.role or null;
          sameRole = roleA != null && roleA == roleB;
          rolesToCheck = [
            "upstream-selector"
          ];
        in
        if sameRole && builtins.elem roleA rolesToCheck then
          let
            p = findPath neigh a b;
          in
          if p != null && !(pathContainsPolicy nodes p) then
            acc
            && ensure false {
              code = "E_TOPO_POLICY_BYPASS";
              site = siteKey;
              path = [
                "topology"
                "links"
              ];
              message =
                "same-role nodes '${a}' and '${b}' (both '${builtins.toString roleA}') communicate without traversing policy";
              hints = [
                "All traffic between same-role upstream-selector nodes must traverse a node with role = \"policy\"."
                "Found path: ${builtins.concatStringsSep " → " p}"
                "Insert a policy node in the communication path between these same-role nodes."
              ];
            }
          else
            acc
        else
          acc;

      pairs = lib.concatMap (
        i:
        let
          a = builtins.elemAt nodeNames i;
        in
        map (j: [
          a
          (builtins.elemAt nodeNames j)
        ]) (lib.range (i + 1) (builtins.length nodeNames - 1))
      ) (lib.range 0 (builtins.length nodeNames - 2));
    in
    builtins.foldl' checkPair true pairs;
in
{
  inherit validatePolicyTraversal;
}
