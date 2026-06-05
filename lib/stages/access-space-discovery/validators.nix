{ lib }:

ctx:
let
  inherit (ctx)
    require
    has
    isNonEmptyString
    isStringList
    accessSpaceNames
    serviceNames
    ;

  requireMatrixField =
    idx: entry: field:
    require (has field entry) "E_ACCESS_SPACE_DISCOVERY_REQUIRED_FIELD"
      [
        "profileManifest"
        "tenantAccessMatrix"
        idx
        field
      ]
      "access-space discovery matrix row ${toString idx} is missing required field '${field}'"
      [ "Declare scope, discoveryExports, and allowedServices for each access-space discovery row." ];
in
{
  validateMatrixEntry =
    idx: entry:
    let
      _required =
        builtins.deepSeq
          [
            (requireMatrixField idx entry "scope")
            (requireMatrixField idx entry "discoveryExports")
            (requireMatrixField idx entry "allowedServices")
          ]
          true;
      scope = entry.scope;
      discoveryExports = entry.discoveryExports or [ ];
      allowedServices = entry.allowedServices or [ ];
      _scope =
        require (builtins.elem scope accessSpaceNames) "E_ACCESS_SPACE_DISCOVERY_UNKNOWN_SCOPE"
          [
            "profileManifest"
            "tenantAccessMatrix"
            idx
            "scope"
          ]
          "access-space discovery matrix references unknown scope '${scope}'"
          [ "Declare the scope under profileManifest.accessSpaces before using it in tenantAccessMatrix." ];
      _exports =
        require (builtins.isList discoveryExports) "E_ACCESS_SPACE_DISCOVERY_EXPORTS_LIST"
          [
            "profileManifest"
            "tenantAccessMatrix"
            idx
            "discoveryExports"
          ]
          "access-space '${scope}' discoveryExports must be a list"
          [ "Use a list of service names or explicit export records." ];
      _allowed =
        require (isStringList allowedServices) "E_ACCESS_SPACE_DISCOVERY_ALLOWED_SERVICES_LIST"
          [
            "profileManifest"
            "tenantAccessMatrix"
            idx
            "allowedServices"
          ]
          "access-space '${scope}' allowedServices must be a list of service names"
          [ "Keep payload/service reachability separate from discoveryExports." ];
    in
    builtins.deepSeq [
      _required
      _scope
      _exports
      _allowed
    ] true;

  validateSharedService =
    idx: service:
    let
      serviceName = service.service or null;
      discovery = service.discovery or { };
      payload = service.payload or { };
      requesterScopes = service.requesterScopes or [ ];
      responderScope = service.responderScope or null;
      req = suffix: cond: code: field: message: hints:
        require cond code
          ([
            "profileManifest"
            "sharedServiceMatrix"
            idx
          ] ++ suffix)
          message
          hints;
      checks = [
        (req [ "service" ] (isNonEmptyString serviceName) "E_ACCESS_SPACE_DISCOVERY_SERVICE_REQUIRED" "service"
          "shared-service discovery row ${toString idx} is missing service identity"
          [ "Name the advertised shared service." ])
        (req [ "service" ] (serviceName == null || builtins.elem serviceName serviceNames)
          "E_ACCESS_SPACE_DISCOVERY_UNKNOWN_SERVICE" "service"
          "shared-service discovery row references unknown service '${toString serviceName}'"
          [ "Declare the service in communicationContract.services before exporting discovery." ])
        (req [ "requesterScopes" ] (isStringList requesterScopes)
          "E_ACCESS_SPACE_DISCOVERY_REQUESTER_SCOPES" "requesterScopes"
          "shared-service '${toString serviceName}' requesterScopes must be a list of access-space names"
          [ "Declare requester scopes explicitly; do not infer them from host placement." ])
        (req [ "responderScope" ] (isNonEmptyString responderScope && builtins.elem responderScope accessSpaceNames)
          "E_ACCESS_SPACE_DISCOVERY_RESPONDER_SCOPE" "responderScope"
          "shared-service '${toString serviceName}' responderScope must name a modeled access space"
          [ "Bind discovery to an explicit responder access space." ])
        (req [ "serviceClass" ] (isNonEmptyString (service.serviceClass or null))
          "E_ACCESS_SPACE_DISCOVERY_SERVICE_CLASS" "serviceClass"
          "shared-service '${toString serviceName}' must declare serviceClass"
          [ "Keep service type explicit for discovery export decisions." ])
        (req [ "discovery" "protocol" ] (isNonEmptyString (discovery.protocol or null))
          "E_ACCESS_SPACE_DISCOVERY_PROTOCOL" "discovery.protocol"
          "shared-service '${toString serviceName}' must declare discovery.protocol"
          [ "Do not infer discovery behavior from payload or service existence." ])
        (req [ "discovery" "direction" ] (isNonEmptyString (discovery.direction or null))
          "E_ACCESS_SPACE_DISCOVERY_DIRECTION" "discovery.direction"
          "shared-service '${toString serviceName}' must declare discovery.direction"
          [ "Keep discovery direction explicit and separate from payload direction." ])
        (req [ "payload" "protocol" ] (isNonEmptyString (payload.protocol or null))
          "E_ACCESS_SPACE_DISCOVERY_PAYLOAD_PROTOCOL" "payload.protocol"
          "shared-service '${toString serviceName}' must declare payload.protocol"
          [ "Payload reachability remains separately modeled even for discovery-only decisions." ])
        (req [ "payload" "ports" ] (builtins.isList (payload.ports or null))
          "E_ACCESS_SPACE_DISCOVERY_PAYLOAD_PORTS" "payload.ports"
          "shared-service '${toString serviceName}' must declare payload.ports"
          [ "Payload ports must not be inferred from discovery visibility." ])
        (req [ "discovery" ] (!(service.inferPayloadFromDiscovery or false) && !(discovery.grantsPayloadReachability or false))
          "E_ACCESS_SPACE_DISCOVERY_PAYLOAD_INFERENCE" "discovery"
          "shared-service '${toString serviceName}' must not grant payload reachability from discovery visibility"
          [ "Model payload reachability with allowedServices and communicationContract relations, not discovery exports." ])
      ];
    in
    builtins.deepSeq checks true;
}
