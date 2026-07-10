{ lib }:

siteKey: serviceIndex: communicationContract: profileManifest:
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
      assertUnique
      matrix
      sharedServices
      accessSpaces
      accessSpaceNames
      serviceNames
      communicationContract
      serviceByName
      matrixByScope
      indexedMatrix
      ;
  };

  validators = import ./validators.nix { inherit lib; } ctx;
  exports = import ./exports.nix { inherit lib; } ctx;
  decisions = import ./decisions.nix { inherit lib; } ctx;
  sharedServicePolicyAtoms = import ./shared-service-policy-atoms.nix { inherit lib; } ctx;

  # FS-610-HDS-010-SDS-010-SMS-040: broad flooding denial
  requireBroadFloodingDenial = import ../../broad-flooding-denial.nix { inherit lib; };

  # FS-590-HDS-010-SDS-010-SMS-030: discovery transport explicitness
  requireDiscoveryTransportExplicitness = import ./discovery-transport-explicitness.nix { inherit lib; };

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
                    || lib.any
                      (e: builtins.isAttrs e && (e.service or e.name or null) == service.service)
                      (requester.discoveryExports or [ ])
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
      _discoveryTransportExplicitness
      _shared
      _exports
      _crossScopePolicy
      _broadFloodingDenial
    ]
    true;

  # Validate exported contracts for broad flooding and reverse discovery (SMS-040)
  _broadFloodingDenial = builtins.deepSeq
    (map (contract: requireBroadFloodingDenial siteKey contract) exported)
    true; 

  # Validate shared services for discovery transport explicitness (SMS-030)
  _discoveryTransportExplicitness = builtins.deepSeq
    (map (service: requireDiscoveryTransportExplicitness siteKey service) sharedServices)
    true;

  confined = map decisions.confinementDecision indexedMatrix;
  exported = lib.concatMap (entry: map (exports.validateDiscoveryExport entry) (entry.discoveryExports or [ ])) indexedMatrix;
in
if profileManifest == null then
  {
    confined = [ ];
    exported = [ ];
    sharedServicePolicyAtoms = sharedServicePolicyAtoms;
  }
else
  builtins.seq _forced {
    inherit confined exported sharedServicePolicyAtoms;
  }
