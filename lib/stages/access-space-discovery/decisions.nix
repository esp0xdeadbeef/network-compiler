{ lib }:

ctx:
let
  exports = import ./exports.nix { inherit lib; } ctx;
  inherit (ctx) sharedServices;
in
{
  confinementDecision =
    entry:
    let
      scope = entry.scope;
    in
    {
      inherit scope;
      confinedByDefault = true;
      discoveryExports = map (export: (exports.normalizeExport export).service) (entry.discoveryExports or [ ]);
      deniedCrossScopeByDefault = lib.filter
        (service:
          builtins.elem scope (service.requesterScopes or [ ])
          && (service.discovery.protocol or null) != "none"
          && (service.responderScope or null) != scope
          && !builtins.elem service.service (entry.discoveryExports or [ ]))
        sharedServices;
      source = {
        outputPath = [
          "accessSpaceDiscovery"
          "confined"
          scope
        ];
        sourceClass = "user-intent";
        sourcePath = [
          "profileManifest"
          "tenantAccessMatrix"
          entry._matrixIndex
        ];
        authority = "network-compiler";
      };
    };
}
