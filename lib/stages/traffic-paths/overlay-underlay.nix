{ lib }:

overlays: accessForEndpoint: relation:

let
  overlaysByName = builtins.listToAttrs (
    map
      (overlay: {
        name = overlay.name;
        value = overlay;
      })
      overlays
  );

  endpoint = relation.from;
  trafficType = relation.trafficType or null;
  overlay =
    if builtins.isAttrs endpoint && builtins.hasAttr (endpoint.name or "") overlaysByName then
      overlaysByName.${endpoint.name}
    else
      null;
  underlayTrafficTypes = if overlay == null then [ ] else overlay.underlayTrafficTypes or [ ];
  trafficTypeIsUnderlay =
    if underlayTrafficTypes == [ ] then
      trafficType != "any"
    else
      builtins.elem trafficType underlayTrafficTypes;
in
if
  trafficTypeIsUnderlay
  &&
  builtins.isAttrs endpoint
  && (endpoint.kind or null) == "external"
  && builtins.hasAttr (endpoint.name or "") overlaysByName
    && builtins.isAttrs (overlaysByName.${endpoint.name}.underlayAccess or null)
then
  accessForEndpoint overlaysByName.${endpoint.name}.underlayAccess
else
  null
