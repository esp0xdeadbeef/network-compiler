{ lib }:

let
  util = import ../util.nix { inherit lib; };
  graph = import ./graph.nix { inherit lib; };
  inherit (util) ensure throwError;
  inherit (graph) normalizeLinkPair;

  logicalLinkName =
    pair:
    let
      ordered = normalizeLinkPair pair;
    in
    "${builtins.elemAt ordered 0}<->${builtins.elemAt ordered 1}";

  assertUniqueLogicalLinks =
    siteKey: links:
    let
      names = lib.sort builtins.lessThan (map logicalLinkName links);

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
                code = "E_TOPO_DUPLICATE_LINK";
                site = siteKey;
                path = [
                  "topology"
                  "links"
                ];
                message = "duplicate logical link '${cur}'";
                hints = [ "Remove duplicate or reversed-duplicate topology.links entries." ];
              }
          else
            check cur (builtins.tail rest);
    in
    if names == [ ] then true else check (builtins.head names) (builtins.tail names);

  validateLink =
    siteKey: nodeNames: pair:
    let
      _len = ensure (builtins.length pair == 2) {
        code = "E_TOPO_LINK_SHAPE";
        site = siteKey;
        path = [
          "topology"
          "links"
        ];
        message = "topology links must contain exactly two endpoints";
        hints = [ "Use one pair per physical/logical adjacency." ];
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

      _notSelf = ensure (a != b) {
        code = "E_TOPO_SELF_LINK";
        site = siteKey;
        path = [
          "topology"
          "links"
        ];
        message = "topology link endpoints must be distinct";
        hints = [ "Replace self-links with links between two different nodes." ];
      };
    in
    _len && _a && _b && _notSelf;

  validateLinks =
    siteKey: nodeNames: links:
    let
      _linksOk = builtins.foldl'
        (
          acc: pair: acc && validateLink siteKey nodeNames pair
        )
        true
        links;
      normalizedLinks = map normalizeLinkPair links;
      _uniqLinks = assertUniqueLogicalLinks siteKey normalizedLinks;
      _forced = builtins.deepSeq
        {
          inherit _linksOk _uniqLinks;
        }
        true;
    in
    if _forced then normalizedLinks else normalizedLinks;
in
{
  inherit validateLinks;
}
