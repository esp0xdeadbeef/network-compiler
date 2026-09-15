{
  lib,
  topoC,
  addressSafety,
  normalizeUplinksForNode,
  normalizeTransportOverlays,
  buildCoreUplinks,
  validateSupersededContract,
}:

{

  prepare =
    siteKey: declared: semantic:
    let

      _superseded = validateSupersededContract.perSite siteKey declared;
      topo = declared.topology or { };
      nodes = topo.nodes or { };
      nodeNamesSorted = lib.sort builtins.lessThan (builtins.attrNames nodes);
      coreNodes = lib.filter (n: (nodes.${n}.role or null) == "core") nodeNamesSorted;
      overlays = normalizeTransportOverlays siteKey topo declared;
      overlayNames = lib.sort builtins.lessThan (lib.unique (map (o: o.name) overlays));

      overlayEndpoints = import ../../correctness/overlay-endpoints.nix { inherit lib; };
      overlayEndpointNodes = overlayEndpoints.overlayEndpointNodes overlays;
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

      coreUplinks = builtins.deepSeq _superseded (
        buildCoreUplinks siteKey nodes coreNodes { inherit overlayEndpointNodes; }
      );

      normalizeSelects =
        nodeName: node:
        let
          raw = node.selects or [ ];
        in
        if !(builtins.isList raw) then
          throw (
            "E_CONTRACT_SELECTS: topology.nodes.${nodeName}.selects must be a list "
            + "(FS-322 Scope Reachability; owning item: FS-322)."
          )
        else
          map (
            entry:
            if builtins.isString entry then
              {
                uplink = entry;
                behaviors = [ ];
              }
            else if builtins.isAttrs entry then
              {
                uplink = entry.uplink or null;
                scope = entry.scope or null;
                behaviors =
                  if builtins.isList (entry.behaviors or null) then
                    entry.behaviors
                  else
                    throw (
                      "E_CONTRACT_SELECTS: topology.nodes.${nodeName}.selects[] behavior must be a list "
                      + "(FS-481 Routing Behavior Selection)."
                    );
              }
            else
              throw (
                "E_CONTRACT_SELECTS: topology.nodes.${nodeName}.selects entries must be a string (uplink) or an attrset "
                + "(FS-322 Scope Reachability)."
              )
          ) raw;

      normalizeOffers =
        nodeName: node:
        let
          raw = node.offers or null;
        in
        if raw == null then
          null
        else if builtins.isList raw && builtins.all builtins.isString raw then
          raw
        else
          throw (
            "E_CONTRACT_OFFERS: topology.nodes.${nodeName}.offers must be a list of prefix strings "
            + "(FS-322 Scope Reachability; owning item: FS-322)."
          );

      normalizedTopologyNodes = builtins.deepSeq _superseded (
        lib.mapAttrs (
          nodeName: node:
          node
          // {
            uplinks = normalizeUplinksForNode.forNodeAttrs siteKey nodeName (node.uplinks or null);
            selects = normalizeSelects nodeName node;
          }
          // lib.optionalAttrs (node ? offers) {
            offers = normalizeOffers nodeName node;
          }
        ) nodes
      );
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
        inherit _superseded;
      };
    };
}
