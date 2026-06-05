{ lib }:

siteKey: serviceIndex: profileManifest:
let
  util = import ../../correctness/util.nix { inherit lib; };
  inherit (util) ensure assertUnique;

  has = attr: attrs: builtins.isAttrs attrs && builtins.hasAttr attr attrs;
  isNonEmptyString = value: builtins.isString value && value != "";
  isStringList = value: builtins.isList value && builtins.all isNonEmptyString value;

  require =
    cond: code: path: message: hints:
    ensure cond {
      inherit code;
      site = siteKey;
      inherit path message hints;
    };

  matrix = profileManifest.tenantAccessMatrix or [ ];
  sharedServices = profileManifest.sharedServiceMatrix or [ ];
  accessSpaces = profileManifest.accessSpaces or { };
  accessSpaceNames = lib.sort builtins.lessThan (builtins.attrNames accessSpaces);
  serviceNames = builtins.attrNames serviceIndex;

  serviceByName =
    builtins.listToAttrs (
      map
        (service: {
          name = service.service;
          value = service;
        })
        (lib.filter (service: builtins.isAttrs service && isNonEmptyString (service.service or null)) sharedServices)
    );

  matrixByScope =
    builtins.listToAttrs (
      lib.imap0
        (
          idx: entry: {
            name = entry.scope;
            value = entry // {
              _matrixIndex = idx;
            };
          }
        )
        (lib.filter (entry: builtins.isAttrs entry && isNonEmptyString (entry.scope or null)) matrix)
    );
  indexedMatrix = lib.sort (a: b: a.scope < b.scope) (builtins.attrValues matrixByScope);

  ctx = {
    inherit
      siteKey
      require
      has
      isNonEmptyString
      isStringList
      matrix
      sharedServices
      accessSpaces
      accessSpaceNames
      serviceNames
      serviceByName
      matrixByScope
      indexedMatrix
      ;
  };

  validators = import ./validators.nix { inherit lib; } ctx;
  exports = import ./exports.nix { inherit lib; } ctx;
  decisions = import ./decisions.nix { inherit lib; } ctx;

  _accessSpaces =
    require (builtins.isAttrs accessSpaces && accessSpaces != { })
      "E_ACCESS_SPACE_DISCOVERY_ACCESS_SPACES_REQUIRED"
      [
        "profileManifest"
        "accessSpaces"
      ]
      "profileManifest.accessSpaces is required for access-space discovery decisions"
      [ "Declare modeled access spaces before discovery confinement or export policy." ];

  _uniqueScopes = assertUnique "access-space discovery scope" (map (entry: entry.scope) matrix);
  _uniqueSharedServices = assertUnique "access-space shared service" (
    map (service: service.service) (
      lib.filter (service: builtins.isAttrs service && isNonEmptyString (service.service or null)) sharedServices
    )
  );

  _matrix = builtins.deepSeq (lib.imap0 validators.validateMatrixEntry matrix) true;
  _shared = builtins.deepSeq (lib.imap0 validators.validateSharedService sharedServices) true;
  _exports = builtins.deepSeq
    (lib.concatMap (entry: map (exports.validateDiscoveryExport entry) (entry.discoveryExports or [ ])) indexedMatrix)
    true;
  _crossScopePolicy =
    builtins.deepSeq
      (
        lib.concatMap
          (
            service:
            map
              (
                requesterScope:
                let
                  requester = matrixByScope.${requesterScope} or null;
                  responderScope = service.responderScope or null;
                in
                require
                  (
                    requester == null
                    || responderScope == requesterScope
                    || (service.discovery.protocol or null) == "none"
                    || builtins.elem service.service (requester.discoveryExports or [ ])
                  )
                  "E_ACCESS_SPACE_DISCOVERY_CROSS_SCOPE_DENIED"
                  [
                    "profileManifest"
                    "sharedServiceMatrix"
                    service.service
                    "requesterScopes"
                  ]
                  "cross-scope discovery for service '${service.service}' from '${requesterScope}' to '${toString responderScope}' is denied without discoveryExports authority"
                  [ "List the service in the requester access space discoveryExports, or set discovery.protocol = \"none\" for non-discovery payload services." ]
              )
              (service.requesterScopes or [ ])
          )
          sharedServices
      )
      true;

  _forced = builtins.deepSeq
    [
      _accessSpaces
      _uniqueScopes
      _uniqueSharedServices
      _matrix
      _shared
      _exports
      _crossScopePolicy
    ]
    true;

  confined = map decisions.confinementDecision indexedMatrix;
  exported = lib.concatMap (entry: map (exports.validateDiscoveryExport entry) (entry.discoveryExports or [ ])) indexedMatrix;
in
if profileManifest == null then
  {
    confined = [ ];
    exported = [ ];
  }
else
  builtins.seq _forced {
    inherit confined exported;
  }
