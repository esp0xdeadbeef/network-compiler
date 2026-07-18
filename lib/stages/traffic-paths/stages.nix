{
  lib,
  serviceIndex,
  overlayUnderlayAccessFor,
}:

let
  accessToCore = [
    "access"
    "downstream-selector"
    "policy"
    "upstream-selector"
    "core"
  ];
  coreToAccess = lib.reverseList accessToCore;

  endpointStage =
    endpoint:
    if !builtins.isAttrs endpoint then
      "access"
    else if builtins.elem (endpoint.kind or null) [ "external" "public-ipv4" ] then
      "core"
    else if
      (endpoint.kind or null) == "service"
      && builtins.hasAttr (endpoint.name or "") serviceIndex
      && (serviceIndex.${endpoint.name}.providerRole or null) == "core"
    then
      "core"
    else
      "access";

  pathStagesFor =
    relation:
    let
      fromStage = endpointStage relation.from;
      toStage = endpointStage relation.to;
      overlayAccess = overlayUnderlayAccessFor relation;
    in
    if overlayAccess != null && fromStage == "core" && toStage == "core" then
      [
        "core"
        "access"
        "downstream-selector"
        "policy"
        "upstream-selector"
        "core"
      ]
    else if overlayAccess != null && fromStage == "core" && toStage == "access" then
      [
        "core"
        "access"
        "downstream-selector"
        "policy"
        "downstream-selector"
        "access"
      ]
    else if fromStage == "core" && toStage == "access" then
      coreToAccess
    else if fromStage == "access" && toStage == "core" then
      accessToCore
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
in
{
  inherit endpointStage pathStagesFor;
}
