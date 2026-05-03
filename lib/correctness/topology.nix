{ lib }:

let
  util = import ./util.nix { inherit lib; };
  graph = import ./topology/graph.nix { inherit lib; };
  links = import ./topology/links.nix { inherit lib; };
  uplinks = import ./topology/uplinks.nix { inherit lib; };
  inherit (util) ensure assertUnique throwError;
  inherit (graph) neighborsMap bfs;
  inherit (links) validateLinks;
  inherit (uplinks) normalizeUplinks;

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
            throwError {
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

      _hasDownstreamSelector = ensure (builtins.elem "downstream-selector" roles) {
        code = "E_TOPO_MISSING_DOWNSTREAM_SELECTOR";
        site = siteKey;
        path = [
          "topology"
          "nodes"
        ];
        message = "topology must include a downstream-selector node";
        hints = [
          "Add a node with role = \"downstream-selector\"."
          "Connect it between access and policy in topology.links."
        ];
      };

      _hasUpstreamSelector = ensure (builtins.elem "upstream-selector" roles) {
        code = "E_TOPO_MISSING_UPSTREAM_SELECTOR";
        site = siteKey;
        path = [
          "topology"
          "nodes"
        ];
        message = "topology must include an upstream-selector node";
        hints = [
          "Add a node with role = \"upstream-selector\"."
          "Connect it between policy and core in topology.links."
        ];
      };

      links = topo.links or [ ];
      normalizedLinks = validateLinks siteKey nodeNames links;

      touched = lib.unique (
        lib.concatMap (pair: [
          (builtins.elemAt pair 0)
          (builtins.elemAt pair 1)
        ]) normalizedLinks
      );

      _noIsolated = builtins.foldl' (
        acc: n:
        acc
        && ensure (builtins.elem n touched) {
          code = "E_TOPO_DISCONNECTED";
          site = siteKey;
        }
      ) true nodeNames;

      neigh = neighborsMap nodeNames normalizedLinks;

      start = if nodeNames == [ ] then null else builtins.elemAt (lib.sort builtins.lessThan nodeNames) 0;

      seen = if start == null then [ ] else bfs neigh start;

      _connected = ensure (builtins.length seen == builtins.length nodeNames) {
        code = "E_TOPO_DISCONNECTED";
        site = siteKey;
      };

      coreNodes = lib.filter (n: (nodes.${n}.role or null) == "core") (
        lib.sort builtins.lessThan nodeNames
      );

      coreUplinks = builtins.listToAttrs (
        map (n: {
          name = n;
          value =
            let
              us = normalizeUplinks siteKey n (nodes.${n}.uplinks or null);

              _required = ensure (builtins.length us > 0) {
                code = "E_CORE_UPLINKS_REQUIRED";
                site = siteKey;
                path = [
                  "topology"
                  "nodes"
                  n
                  "uplinks"
                ];
                message = "core node '${n}' must define at least one uplink";
                hints = [
                  "Set topology.nodes.${n}.uplinks = { uplink0 = { ipv4 = [\"0.0.0.0/0\"]; ipv6 = [\"::/0\"]; }; }."
                ];
              };
            in
            if _required then us else us;
        }) coreNodes
      );

      allUplinkNames = lib.concatMap (n: map (u: u.name) (coreUplinks.${n} or [ ])) coreNodes;
      _uniqSiteUplinks = assertUniqueSiteUplinkNames siteKey allUplinkNames;

      _force = builtins.deepSeq {
        inherit
          _uniqNodes
          _hasCore
          _hasPolicy
          _hasAccess
          _hasDownstreamSelector
          _hasUpstreamSelector
          _noIsolated
          _connected
          coreUplinks
          _uniqSiteUplinks
          ;
      } true;
    in
    builtins.seq _force true;
in
{
  inherit validateTopology;
}
