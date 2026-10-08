{
  lib,
  topoC,
  addressSafety,
  normalizeUplinksForNode,
  normalizeTransportOverlays,
  buildCoreUplinks,
  validateSupersededContract,
}:

let
  util = import ../../correctness/util.nix { inherit lib; };
  inherit (util) throwError;
in
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

      coreUplinkOwner =
        uplinkName:
        let
          owners = lib.filter (
            name: builtins.elem uplinkName (map (u: u.name) (coreUplinks.${name} or [ ]))
          ) coreNodes;
        in
        if owners == [ ] then null else builtins.head owners;

      contractPrefixes = import ./fabric/contract-prefixes.nix {
        inherit lib siteKey nodes normalizeUplinksForNode;
      };
      selectsMod = import ./fabric/contract-selects.nix {
        inherit
          lib
          siteKey
          nodes
          coreUplinks
          coreNodes
          normalizeUplinksForNode
          coreUplinkOwner
          ;
      };

      selectionTarget =
        nodeName: entry:
        selectsMod.selectionTarget nodeName entry;

      normalizeSelects =
        selectsMod.normalizeSelects;

      recognizedBehaviors = selectsMod.recognizedBehaviors;

      allBehaviorsOf =
        selectsMod.allBehaviorsOf;

      validateBehaviors =
        selectsMod.validateBehaviors;

      ownedPrefixesOf =
        contractPrefixes.ownedPrefixesOf;
      normalizeOffers =
        contractPrefixes.normalizeOffers;
      prefixOwnership =
        contractPrefixes.prepare declared;
      inherit (prefixOwnership)
        declaredOwnershipPrefixStrings
        declaredTenantPrefixesByName
        validatePrefixOwnership
        normalizeAdvertises
        ;

      normalizedTopologyNodes = builtins.deepSeq _superseded (
        lib.mapAttrs (
          nodeName: node:
          node
          // {
            uplinks = normalizeUplinksForNode.forNodeAttrs siteKey nodeName (node.uplinks or null);
            selects = normalizeSelects nodeName node;
            offers = builtins.deepSeq (validatePrefixOwnership nodeName node) (normalizeOffers nodeName node);
            behaviors = builtins.deepSeq (validateBehaviors nodeName node) (allBehaviorsOf node);
            advertises = normalizeAdvertises nodeName node;
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
