{ lib }:

siteKey: nodes: coreUplinks: serviceIndex: hosts: normalizedRelations:

let
  util = import ../correctness/util.nix { inherit lib; };
  selectors = import ./traffic-paths/selectors.nix { inherit lib; } siteKey nodes coreUplinks serviceIndex hosts;
  inherit (util) throwError;
  inherit (selectors) firstRole coresForExternal accessForEndpoint;

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
    in
    if fromStage == "core" && toStage == "access" then
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
      pathCores = if fromCores != [ ] then fromCores else if toCores != [ ] then toCores else [ (firstRole "core") ];
      fromAccess = if fromStage == "access" then accessForEndpoint relation.from else null;
      toAccess = if toStage == "access" then accessForEndpoint relation.to else null;

      nodeForStage =
        core: idx:
        stage:
        if stage == "core" then
          core
        else if stage == "access" then
          if idx == 0 && fromAccess != null then
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

      nodePathAlternatives = map (core: lib.imap0 (nodeForStage core) stages) pathCores;
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
