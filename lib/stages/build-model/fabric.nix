{
  lib,
  topoC,
  addressSafety,
  normalizeUplinksForNode,
  normalizeTransportOverlays,
  buildCoreUplinks,
}:

{

  prepare =
    siteKey: declared: semantic:
    let
      topo = declared.topology or { };
      nodes = topo.nodes or { };
      nodeNamesSorted = lib.sort builtins.lessThan (builtins.attrNames nodes);
      coreNodes = lib.filter (n: (nodes.${n}.role or null) == "core") nodeNamesSorted;
      overlays = normalizeTransportOverlays siteKey topo declared;
      overlayNames = lib.sort builtins.lessThan (lib.unique (map (o: o.name) overlays));
      overlayPool =
        if builtins.isAttrs ((declared.pools or { }).overlay or null) then
          (declared.pools or { }).overlay
        else
          { };
      overlayAddressPools =
        if builtins.isAttrs (declared.overlayAddressPools or null) then
          declared.overlayAddressPools
        else if overlayPool == { } then
          { }
        else
          builtins.listToAttrs (
            map (overlayName: {
              name = overlayName;
              value = overlayPool;
            }) overlayNames
          );

      coreUplinks = buildCoreUplinks siteKey nodes coreNodes;
      normalizedTopologyNodes = lib.mapAttrs (
        nodeName: node:
        node
        // {
          uplinks = normalizeUplinksForNode.forNodeAttrs siteKey nodeName (node.uplinks or null);
        }
      ) nodes;
      uplinkNames = lib.sort builtins.lessThan (
        lib.unique (lib.concatMap (n: map (u: u.name) (coreUplinks.${n} or [ ])) coreNodes)
      );
    in
    {
      inherit
        topo
        nodes
        coreNodes
        overlays
        overlayNames
        overlayAddressPools
        coreUplinks
        normalizedTopologyNodes
        uplinkNames
        ;
      validations = {
        _addrSafe = addressSafety.validateSite siteKey declared;
        _topoValid = topoC.validateTopology siteKey topo overlays;
      };
    };
}
