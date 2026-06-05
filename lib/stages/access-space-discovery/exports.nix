{ lib }:

ctx:
let
  inherit (ctx)
    require
    isNonEmptyString
    accessSpaces
    serviceByName
    ;

  normalizeExport =
    export:
    if builtins.isString export then
      {
        service = export;
        relayOrProxyBoundary = null;
      }
    else if builtins.isAttrs export then
      {
        service = export.service or export.name or null;
        relayOrProxyBoundary = export.relayOrProxyBoundary or export.boundary or null;
      }
    else
      {
        service = null;
        relayOrProxyBoundary = null;
      };

  accessSpaceBoundary =
    requesterScope: responderScope:
    let
      requesterDiscovery = (accessSpaces.${requesterScope} or { }).localServiceDiscovery or null;
      responderDiscovery = (accessSpaces.${responderScope} or { }).localServiceDiscovery or null;
      _requester =
        require (isNonEmptyString requesterDiscovery) "E_ACCESS_SPACE_DISCOVERY_BOUNDARY_REQUIRED"
          [
            "profileManifest"
            "accessSpaces"
            requesterScope
            "localServiceDiscovery"
          ]
          "access-space '${requesterScope}' must declare localServiceDiscovery before exporting discovery"
          [ "Declare whether this access space is a requester, responder, disabled, relay, or proxy participant." ];
      _responder =
        require (isNonEmptyString responderDiscovery) "E_ACCESS_SPACE_DISCOVERY_BOUNDARY_REQUIRED"
          [
            "profileManifest"
            "accessSpaces"
            responderScope
            "localServiceDiscovery"
          ]
          "access-space '${responderScope}' must declare localServiceDiscovery before exporting discovery"
          [ "Declare the responder-side discovery capability instead of inferring relay behavior downstream." ];
    in
    builtins.seq _requester (
      builtins.seq _responder "access-space-local-service-discovery:${requesterDiscovery}->${responderDiscovery}"
    );
in
{
  inherit normalizeExport;

  validateDiscoveryExport =
    entry:
    rawExport:
    let
      scope = entry.scope;
      idx = entry._matrixIndex;
      export = normalizeExport rawExport;
      serviceName = export.service;
      service = serviceByName.${serviceName} or null;
      responderScope = if service == null then null else service.responderScope;
      _serviceName =
        require (isNonEmptyString serviceName) "E_ACCESS_SPACE_DISCOVERY_EXPORT_SERVICE"
          [
            "profileManifest"
            "tenantAccessMatrix"
            idx
            "discoveryExports"
          ]
          "access-space '${scope}' discovery export must name a service"
          [ "Use a service name string or { service = \"...\"; }." ];
      _serviceKnown =
        require (service != null) "E_ACCESS_SPACE_DISCOVERY_EXPORT_UNKNOWN_SERVICE"
          [
            "profileManifest"
            "tenantAccessMatrix"
            idx
            "discoveryExports"
          ]
          "access-space '${scope}' exports unknown discovery service '${toString serviceName}'"
          [ "Add a matching sharedServiceMatrix row before exporting discovery." ];
      _requesterScope =
        require (service == null || builtins.elem scope (service.requesterScopes or [ ]))
          "E_ACCESS_SPACE_DISCOVERY_EXPORT_REQUESTER_SCOPE"
          [
            "profileManifest"
            "tenantAccessMatrix"
            idx
            "discoveryExports"
          ]
          "access-space '${scope}' exports discovery service '${toString serviceName}' without requester-scope authority"
          [ "Add the access space to sharedServiceMatrix.requesterScopes or remove the export." ];
      relayOrProxyBoundary =
        if export.relayOrProxyBoundary != null then
          export.relayOrProxyBoundary
        else
          accessSpaceBoundary scope responderScope;
      _boundary =
        require (isNonEmptyString relayOrProxyBoundary) "E_ACCESS_SPACE_DISCOVERY_EXPORT_BOUNDARY"
          [
            "profileManifest"
            "tenantAccessMatrix"
            idx
            "discoveryExports"
          ]
          "access-space '${scope}' discovery export '${toString serviceName}' lacks relay or proxy boundary"
          [ "Declare relayOrProxyBoundary on the export or localServiceDiscovery on both access spaces." ];
      payloadAuthorized = builtins.elem serviceName (entry.allowedServices or [ ]);
    in
    builtins.seq _serviceName (
      builtins.seq _serviceKnown (
        builtins.seq _requesterScope (
          builtins.seq _boundary {
            requesterScope = scope;
            responderScope = responderScope;
            service = serviceName;
            serviceType = service.serviceClass;
            discovery = service.discovery;
            inherit relayOrProxyBoundary;
            payload = {
              authorized = payloadAuthorized;
              inferredFromDiscovery = false;
              protocol = service.payload.protocol;
              ports = service.payload.ports;
              direction = service.payload.direction or null;
              returnBehavior = service.payload.returnBehavior or null;
            };
            source = {
              outputPath = [
                "accessSpaceDiscovery"
                "exported"
                scope
                serviceName
              ];
              sourceClass = "user-intent";
              sourcePath = [
                "profileManifest"
                "tenantAccessMatrix"
                idx
                "discoveryExports"
              ];
              authority = "network-compiler";
            };
          }
        )
      )
    );
}
