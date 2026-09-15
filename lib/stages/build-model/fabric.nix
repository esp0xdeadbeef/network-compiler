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

      selectionTarget =
        nodeName: entry:
        let
          name =
            if builtins.isString entry then
              entry
            else if builtins.isAttrs entry then
              (entry.scope or entry.uplink or null)
            else
              null;
          owner = if name != null then coreUplinkOwner name else null;
          target = if owner != null then owner else name;

          surface = name;
        in
        if name == null then
          throwError {
            code = "E_CONTRACT_SELECTS";
            site = siteKey;
            path = [
              "topology"
              "nodes"
              nodeName
              "selects"
            ];
            message = "selects entries must name a scope (FS-322 Scope Reachability; owning item: FS-322).";
            spec = "FS-322 Scope Reachability; owning item: FS-322";
            hints = [ "Give each selects entry a scope string, for example selects = [ \"<exit-scope>\" ]." ];
          }
        else if !(builtins.hasAttr target nodes) then
          throwError {
            code = "E_CONTRACT_UNKNOWN_SELECT";
            site = siteKey;
            path = [
              "topology"
              "nodes"
              nodeName
              "selects"
            ];
            message = "topology.nodes.${nodeName}.selects names '${target}', which is not a modeled scope (FS-322 Scope Reachability; owning item: FS-322).";
            spec = "FS-322 Scope Reachability; owning item: FS-322";
            hints = [
              "Declare the scope under topology.nodes.<name>, or name an uplink a modeled scope owns."
            ];
          }
        else
          { inherit target surface; };

      normalizeSelects =
        nodeName: node:
        let
          raw = node.selects or [ ];
        in
        if !(builtins.isList raw) then
          throwError {
            code = "E_CONTRACT_SELECTS";
            site = siteKey;
            path = [
              "topology"
              "nodes"
              nodeName
              "selects"
            ];
            message = "topology.nodes.${nodeName}.selects must be a list (FS-322 Scope Reachability; owning item: FS-322).";
            spec = "FS-322 Scope Reachability; owning item: FS-322";
            hints = [ "Declare selects as a list of scope names." ];
          }
        else
          map (
            entry:
            let
              resolved = selectionTarget nodeName entry;
              target = resolved.target;
              surface = resolved.surface;
              behaviors =
                if builtins.isAttrs entry then
                  if builtins.isList (entry.behaviors or null) then
                    entry.behaviors
                  else
                    throwError {
                      code = "E_CONTRACT_SELECTS";
                      site = siteKey;
                      path = [
                        "topology"
                        "nodes"
                        nodeName
                        "selects"
                      ];
                      message = "topology.nodes.${nodeName}.selects[] behaviors must be a list (FS-481 Routing Behavior Selection).";
                      spec = "FS-481 Routing Behavior Selection";
                      hints = [ "Declare behaviors as a list of required behavior names." ];
                    }
                else
                  [ ];
            in
            {
              scope = target;
              surface = surface;
              inherit behaviors;
            }
          ) raw;

      recognizedBehaviors = [
        "bgp"
        "liveness"
        "equal-cost-multipath"
      ];

      selectedTargetsOf =
        node:
        lib.unique (
          map (
            entry:
            let
              raw =
                if builtins.isString entry then
                  entry
                else if builtins.isAttrs entry then
                  (entry.surface or entry.scope or entry.uplink or null)
                else
                  null;
              owner = if raw != null then coreUplinkOwner raw else null;
            in
            if owner != null then owner else raw
          ) (node.selects or [ ])
        );

      allBehaviorsOf =
        node:
        let
          nodeLevel = if builtins.isList (node.behaviors or null) then node.behaviors else [ ];
          perEntry = lib.concatMap (
            entry:
            if builtins.isAttrs entry && builtins.isList (entry.behaviors or null) then entry.behaviors else [ ]
          ) (node.selects or [ ]);
        in
        lib.unique (nodeLevel ++ perEntry);

      buildCoreUplink4 =
        nodeName:
        lib.concatMap (u: u.ipv4 or [ ]) (
          builtins.attrValues (
            normalizeUplinksForNode.forNodeAttrs siteKey nodeName (nodes.${nodeName}.uplinks or null)
          )
        );

      validateBehaviors =
        nodeName: node:
        let
          behaviors = allBehaviorsOf node;
          selection = selectedTargetsOf node;
          unknown = lib.filter (b: !(builtins.elem b recognizedBehaviors)) behaviors;

          offersBySelected = lib.concatMap (
            t: if builtins.hasAttr t nodes then [ (buildCoreUplink4 t) ] else [ ]
          ) selection;
          sharedPrefix =
            builtins.length (
              builtins.filter (
                p: builtins.length (builtins.filter (lst: builtins.elem p lst) offersBySelected) > 1
              ) (lib.unique (lib.concatLists offersBySelected))
            ) > 0;
          _unknown =
            if unknown == [ ] then
              true
            else
              throwError {
                code = "E_CONTRACT_BEHAVIOR";
                site = siteKey;
                path = [
                  "topology"
                  "nodes"
                  nodeName
                  "behaviors"
                ];
                message = "topology.nodes.${nodeName} requires unrecognized routing behavior(s) ${builtins.concatStringsSep ", " unknown} (FS-481 Routing Behavior Selection).";
                spec = "FS-481 Routing Behavior Selection; owning item: FS-481";
                hints = [ "Use one of: ${builtins.concatStringsSep ", " recognizedBehaviors}." ];
              };
          _empty =
            if behaviors == [ ] || selection != [ ] then
              true
            else
              throwError {
                code = "E_CONTRACT_BEHAVIOR";
                site = siteKey;
                path = [
                  "topology"
                  "nodes"
                  nodeName
                  "behaviors"
                ];
                message = "topology.nodes.${nodeName} requires routing behavior(s) with an empty selection (FS-481 Routing Behavior Selection).";
                spec = "FS-481 Routing Behavior Selection; owning item: FS-481";
                hints = [ "Declare at least one selected scope, or remove the behavior." ];
              };
          _ecmpOverlap =
            if !(builtins.elem "equal-cost-multipath" behaviors) then
              true
            else if sharedPrefix then
              true
            else
              throwError {
                code = "E_CONTRACT_BEHAVIOR";
                site = siteKey;
                path = [
                  "topology"
                  "nodes"
                  nodeName
                  "behaviors"
                ];
                message = "topology.nodes.${nodeName} requires equal-cost multipath but the selected scopes share no offered prefix (FS-481 Routing Behavior Selection).";
                spec = "FS-481 Routing Behavior Selection; owning item: FS-481";
                hints = [ "Select scopes that offer an overlapping prefix, or remove 'equal-cost-multipath'." ];
              };
        in
        builtins.seq _unknown (builtins.seq _empty (builtins.seq _ecmpOverlap behaviors));

      ownedPrefixesOf =
        nodeName:
        let
          uplinks = normalizeUplinksForNode.forNodeAttrs siteKey nodeName (nodes.${nodeName}.uplinks or null);
        in
        lib.sort builtins.lessThan (
          lib.unique (lib.concatMap (u: (u.ipv4 or [ ]) ++ (u.ipv6 or [ ])) (builtins.attrValues uplinks))
        );

      normalizeOffers =
        nodeName: node:
        let
          raw = node.offers or null;
        in
        if raw == null then
          ownedPrefixesOf nodeName
        else if builtins.isList raw && builtins.all builtins.isString raw then
          raw
        else
          throwError {
            code = "E_CONTRACT_OFFERS";
            site = siteKey;
            path = [
              "topology"
              "nodes"
              nodeName
              "offers"
            ];
            message = "topology.nodes.${nodeName}.offers must be a list of prefix strings (FS-322 Scope Reachability; owning item: FS-322).";
            spec = "FS-322 Scope Reachability; owning item: FS-322";
            hints = [ "Declare offers as a list of CIDR prefix strings." ];
          };

      normalizedTopologyNodes = builtins.deepSeq _superseded (
        lib.mapAttrs (
          nodeName: node:
          node
          // {
            uplinks = normalizeUplinksForNode.forNodeAttrs siteKey nodeName (node.uplinks or null);
            selects = normalizeSelects nodeName node;
            offers = normalizeOffers nodeName node;
            behaviors = builtins.deepSeq (validateBehaviors nodeName node) (allBehaviorsOf node);
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
