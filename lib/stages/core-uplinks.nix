{
  lib,
  normalizeUplinksForNode,
  ensure,
}:

siteKey: nodes: coreNodes:

builtins.listToAttrs (
  map (name: {
    inherit name;
    value =
      let
        uplinks = normalizeUplinksForNode.forNodeList siteKey name (nodes.${name}.uplinks or null);
        required = ensure (builtins.length uplinks > 0) {
          code = "E_CORE_UPLINKS_REQUIRED";
          site = siteKey;
          path = [
            "topology"
            "nodes"
            name
            "uplinks"
          ];
          message = "core node '${name}' must define at least one uplink";
          hints = [
            "Set topology.nodes.${name}.uplinks = { uplink0 = { ipv4 = [\"0.0.0.0/0\"]; ipv6 = [\"::/0\"]; }; }."
          ];
        };
      in
      if required then uplinks else uplinks;
  }) coreNodes
)
