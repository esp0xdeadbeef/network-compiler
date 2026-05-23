{ lib }:
siteKey: nodes: coreUplinks: serviceIndex: hosts: overlays: normalizedRelations:
let
  util = import ../correctness/util.nix { inherit lib; };
  selectors = import ./traffic-paths/selectors.nix { inherit lib; } siteKey nodes coreUplinks serviceIndex hosts;
  overlayUnderlay = import ./traffic-paths/overlay-underlay.nix { inherit lib; };
  inherit (util) throwError;
  inherit (selectors) firstRole coresForExternal accessForEndpoint;
  overlayUnderlayAccessFor = overlayUnderlay overlays accessForEndpoint;

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
      sameCoreExternalPairs =
        fromCores != [ ] && toCores != [ ] && builtins.any
          (
            fromCore: builtins.elem fromCore toCores
          )
          fromCores;
      _noExternalCoreLoop =
        if sameCoreExternalPairs then
          throwError
            {
              code = "E_TRAFFIC_PATH_EXTERNAL_CORE_LOOP";
              site = siteKey;
              path = [ "communicationContract" "relations" relation.source.id ];
              message = "external-to-external relation '${relation.source.id}' resolves source and destination to the same core node";
              hints = [
                "Model overlay ingress and WAN egress as distinct external uplinks on distinct core nodes."
                "For WAN egress, use external.uplinks = [ \"<uplink-name>\" ] so intent selects the desired ISP/core explicitly."
                "Do not let overlay ingress return to the same core as WAN authorization."
              ];
            }
        else
          true;
      corePairs =
        if _noExternalCoreLoop && fromCores != [ ] && toCores != [ ] then
          lib.concatMap
            (
              fromCore:
              map
                (toCore: {
                  inherit fromCore toCore;
                })
                toCores
            )
            fromCores
        else if fromCores != [ ] then
          map
            (core: {
              fromCore = core;
              toCore = core;
            })
            fromCores
        else if toCores != [ ] then
          map
            (core: {
              fromCore = core;
              toCore = core;
            })
            toCores
        else
          [
            {
              fromCore = firstRole "core";
              toCore = firstRole "core";
            }
          ];
      pathCores = lib.unique (lib.concatMap (pair: [ pair.fromCore pair.toCore ]) corePairs);
      fromAccess = if fromStage == "access" then accessForEndpoint relation.from else null;
      toAccess = if toStage == "access" then accessForEndpoint relation.to else null;

      nodeForStage =
        corePair: idx:
        stage:
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
      nodePathAlternatives = map (corePair: lib.imap0 (nodeForStage corePair) stages) corePairs;
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
    };
in
map buildOne normalizedRelations
