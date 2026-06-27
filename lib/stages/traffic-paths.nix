{ lib }:
siteKey: nodes: coreUplinks: serviceIndex: hosts: overlays: normalizedRelations:
let
  util = import ../correctness/util.nix { inherit lib; };
  selectors = import ./traffic-paths/selectors.nix { inherit lib; } siteKey nodes coreUplinks serviceIndex hosts;
  overlayUnderlay = import ./traffic-paths/overlay-underlay.nix { inherit lib; };
  buildCorePairs = import ./traffic-paths/core-pairs.nix { inherit lib; };
  wildcardDestinations = import ./traffic-paths/wildcard-destinations.nix { inherit lib; } {
    inherit siteKey nodes throwError;
  };
  inherit (util) throwError;
  inherit (selectors) firstRole coresForExternal accessForEndpoint;
  overlayUnderlayAccessFor = overlayUnderlay overlays accessForEndpoint;

  # Returns overlay metadata for a relation that involves an overlay, or null.
  overlaysByName = builtins.listToAttrs (
    map (overlay: { name = overlay.name; value = overlay; }) overlays
  );
  endpointOverlayName =
    endpoint:
    if !(builtins.isAttrs endpoint) || (endpoint.kind or null) != "external" then
      null
    else
      let name = endpoint.name or ""; in
      if builtins.hasAttr name overlaysByName then name else null;
  overlayInfoForRelation =
    relation:
    let
      fromOverlayName = endpointOverlayName relation.from;
      toOverlayName = endpointOverlayName relation.to;
      overlayName = if fromOverlayName != null then fromOverlayName else toOverlayName;
      overlay = if overlayName != null then overlaysByName.${overlayName} else null;
      isUnderlayRel =
        overlayName != null
        && fromOverlayName != null  # underlay traffic originates FROM the overlay external
        && (relation.trafficType or "any") != "any";
    in
    if overlay == null then null else {
      overlayIdentity = overlayName;
      peerSiteIdentity = overlay.peerSite or null;
      transportKind = if isUnderlayRel then "overlay-underlay" else "overlay-payload";
    };

  accessToCoreStages = [
    "access"
    "downstream-selector"
    "policy"
    "upstream-selector"
    "core"
  ];

  coreToAccessStages = lib.reverseList accessToCoreStages;

  endpointStage =
    endpoint:
    if !builtins.isAttrs endpoint then
      "access"
    else if (endpoint.kind or null) == "external" then
      "core"
    else
      "access";

  pathStagesFor =
    relation:
    let
      fromStage = endpointStage relation.from;
      toStage = endpointStage relation.to;
      fromOverlayUnderlayAccess = overlayUnderlayAccessFor relation;
    in
    if fromOverlayUnderlayAccess != null && fromStage == "core" && toStage == "core" then
      [
        "core"
        "access"
        "downstream-selector"
        "policy"
        "upstream-selector"
        "core"
      ]
    else if fromOverlayUnderlayAccess != null && fromStage == "core" && toStage == "access" then
      [
        "core"
        "access"
        "downstream-selector"
        "policy"
        "downstream-selector"
        "access"
      ]
    else if fromStage == "core" && toStage == "access" then
      coreToAccessStages
    else if fromStage == "access" && toStage == "core" then
      accessToCoreStages
    else if fromStage == "access" && toStage == "access" then
      [
        "access"
        "downstream-selector"
        "policy"
        "downstream-selector"
        "access"
      ]
    else
      [
        "core"
        "upstream-selector"
        "policy"
        "upstream-selector"
        "core"
      ];

  buildOne =
    relation:
    let
      stages = pathStagesFor relation;
      fromStage = endpointStage relation.from;
      toStage = endpointStage relation.to;
      fromCores = if fromStage == "core" then coresForExternal relation.from else [ ];
      toCores = if toStage == "core" then coresForExternal relation.to else [ ];
      fromOverlayUnderlayAccess = overlayUnderlayAccessFor relation;
      corePairs = buildCorePairs {
        inherit siteKey throwError firstRole relation fromCores toCores;
      };
      pathCores = lib.unique (lib.concatMap (pair: [ pair.fromCore pair.toCore ]) corePairs);
      fromAccess = if fromStage == "access" then accessForEndpoint relation.from else null;
      toAccessOptions =
        if toStage != "access" then
          [ null ]
        else if relation.to == "any" then
          wildcardDestinations.accessNodesFor relation
        else
          [ (accessForEndpoint relation.to) ];
      pathVariants = lib.concatMap
        (
          corePair:
          map
            (toAccess: {
              inherit corePair toAccess;
            })
            toAccessOptions
        )
        corePairs;

      nodeForStage =
        variant: idx:
        stage:
        let
          inherit (variant) corePair toAccess;
        in
        if stage == "core" then
          if idx == 0 && fromStage == "core" then
            corePair.fromCore
          else if idx == (builtins.length stages - 1) && toStage == "core" then
            corePair.toCore
          else
            corePair.toCore
        else if stage == "access" then
          if fromOverlayUnderlayAccess != null && idx == 1 then
            fromOverlayUnderlayAccess
          else if idx == 0 && fromAccess != null then
            fromAccess
          else if idx == (builtins.length stages - 1) && toAccess != null then
            toAccess
          else if fromAccess != null then
            fromAccess
          else if toAccess != null then
            toAccess
          else
            firstRole "access"
        else if stage == "downstream-selector" then
          firstRole "downstream-selector"
        else if stage == "policy" then
          firstRole "policy"
        else if stage == "upstream-selector" then
          firstRole "upstream-selector"
        else
          throwError {
            code = "E_TRAFFIC_PATH_UNKNOWN_STAGE";
            site = siteKey;
            path = [ "trafficPaths" ];
            message = "unknown canonical traffic stage '${stage}'";
            hints = [ "Keep traffic paths on the compiler canonical staged fabric." ];
          };
      nodePathAlternatives = map (variant: lib.imap0 (nodeForStage variant) stages) pathVariants;
      overlayInfo = overlayInfoForRelation relation;
    in
    {
      relationId = relation.source.id;
      source = relation.from;
      destination = relation.to;
      action = relation.action;
      trafficType = relation.trafficType;
      stagePath = stages;
      corePathNodes = pathCores;
      nodePath = builtins.head nodePathAlternatives;
      nodePathAlternatives = nodePathAlternatives;
      requiresPolicy = builtins.elem "policy" stages;
      forbidsCoreToCoreP2P = true;
      p2pIsolationKey = relation.source.id;
    }
    // lib.optionalAttrs (overlayInfo != null) overlayInfo;
in
map buildOne normalizedRelations
