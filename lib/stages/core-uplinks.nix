{
  lib,
  normalizeUplinksForNode,
  ensure,
}:

siteKey: nodes: coreNodes:
{
  overlayEndpointNodes ? [ ],
}:

builtins.listToAttrs (
  map (name: {
    inherit name;
    value =
      let
        uplinks = normalizeUplinksForNode.forNodeList siteKey name (nodes.${name}.uplinks or null);

        isOverlayEndpoint = builtins.elem name overlayEndpointNodes;
        required = ensure (builtins.length uplinks > 0 || isOverlayEndpoint) {
          code = "E_CORE_UPLINKS_REQUIRED";
          site = siteKey;
          path = [
            "topology"
            "nodes"
            name
            "uplinks"
          ];
          message = "core node '${name}' must define at least one uplink or be a modeled overlay/remote-egress endpoint";
          hints = [
            "Set topology.nodes.${name}.uplinks = { uplink0 = { ipv4 = [\"0.0.0.0/0\"]; ipv6 = [\"::/0\"]; }; }, or model an overlay whose terminateOn is '${name}'."
          ];
        };
      in
      if required then uplinks else uplinks;
  }) coreNodes
)
