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
    in
    # FS-460: an overlay's underlayAccess is underlay transport used to
    # establish the overlay; it shall not become a payload transit hop. The
    # overlay-underlay payload path therefore uses the ordinary canonical
    # chain for its endpoint stages, and the underlay attachment is modeled
    # separately as an overlay/underlay virtual link.
    if fromStage == "core" && toStage == "access" then
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
