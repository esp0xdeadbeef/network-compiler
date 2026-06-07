{ lib }:

ctx:
let
  inherit (ctx) require has isNonEmptyString assertUnique serviceNames communicationContract;

  atoms = communicationContract.sharedServicePolicyAtoms or [ ];

  isStringList = value: builtins.isList value && builtins.all isNonEmptyString value;

  indexedAtoms = lib.imap0 (idx: atom: atom // { _atomIndex = idx; }) atoms;

  discoveryAtoms = lib.filter (atom: builtins.isAttrs atom && builtins.isAttrs (atom.discovery or null) && (atom.discovery.allowed or false)) indexedAtoms;

  scopeList =
    atom:
    if has "controllerScopes" atom then
      atom.controllerScopes
    else
      atom.requesterScopes or [ ];

  receiverScope =
    atom:
    if has "receiverScope" atom then
      atom.receiverScope
    else
      atom.responderScope or null;

  selectedProtocols =
    discovery:
    if builtins.isList (discovery.selectedProtocols or null) then
      discovery.selectedProtocols
    else if builtins.isList (discovery.protocols or null) then
      discovery.protocols
    else if isNonEmptyString (discovery.protocol or null) then
      [ discovery.protocol ]
    else
      [ ];

  rawSurfaces =
    discovery:
    if builtins.isList (discovery.transports or null) then
      discovery.transports
    else if builtins.isAttrs (discovery.transport or null) then
      [ discovery.transport ]
    else
      [ ];

  normalizeSurface =
    surface:
    let
      protocol = surface.protocol or null;
      transport = surface.proto or surface.transport or null;
    in
    {
      inherit protocol transport;
    }
    // lib.optionalAttrs (has "port" surface) { port = surface.port; }
    // lib.optionalAttrs (has "ports" surface) { ports = surface.ports; }
    // lib.optionalAttrs (has "record" surface) { record = surface.record; }
    // lib.optionalAttrs (has "records" surface) { records = surface.records; }
    // lib.optionalAttrs (has "service" surface) { service = surface.service; }
    // lib.optionalAttrs (has "scope" surface) { scope = surface.scope; }
    // lib.optionalAttrs (has "serviceType" surface) { serviceType = surface.serviceType; }
    // lib.optionalAttrs (has "targetService" surface) { targetService = surface.targetService; }
    // lib.optionalAttrs (has "payloadPort" surface) { payloadPort = surface.payloadPort; };

  validateAtom =
    atom:
    let
      idx = atom._atomIndex;
      path = suffix: [ "communicationContract" "sharedServicePolicyAtoms" idx ] ++ suffix;
      service = atom.service or null;
      scopes = scopeList atom;
      responder = receiverScope atom;
      discovery = atom.discovery;
      protocols = selectedProtocols discovery;
      surfaces = rawSurfaces discovery;
      req = suffix: cond: code: message: hints:
        require cond code (path suffix) message hints;
    in
    builtins.deepSeq
      [
        (req [ "id" ] (isNonEmptyString (atom.id or null))
          "E_SHARED_SERVICE_POLICY_ATOM_ID"
          "shared-service discovery policy atom ${toString idx} is missing id"
          [ "Give each executable discovery policy atom a stable id." ])
        (req [ "service" ] (isNonEmptyString service)
          "E_SHARED_SERVICE_POLICY_ATOM_SERVICE"
          "shared-service discovery policy atom '${toString (atom.id or idx)}' is missing service"
          [ "Bind discovery policy to an explicit communicationContract service." ])
        (req [ "service" ] (service == null || builtins.elem service serviceNames)
          "E_SHARED_SERVICE_POLICY_ATOM_UNKNOWN_SERVICE"
          "shared-service discovery policy atom '${toString (atom.id or idx)}' references unknown service '${toString service}'"
          [ "Declare the service in communicationContract.services before publishing executable discovery policy." ])
        (req [ "serviceClass" ] (isNonEmptyString (atom.serviceClass or null))
          "E_SHARED_SERVICE_POLICY_ATOM_SERVICE_CLASS"
          "shared-service discovery policy atom '${toString (atom.id or idx)}' is missing serviceClass"
          [ "Keep shared-service class explicit; do not infer it from the service name." ])
        (req [ "controllerScopes" ] (isStringList scopes)
          "E_SHARED_SERVICE_POLICY_ATOM_REQUESTER_SCOPES"
          "shared-service discovery policy atom '${toString (atom.id or idx)}' must declare controllerScopes or requesterScopes as a list"
          [ "Declare controller/requester scope explicitly." ])
        (req [ "receiverScope" ] (isNonEmptyString responder)
          "E_SHARED_SERVICE_POLICY_ATOM_RESPONDER_SCOPE"
          "shared-service discovery policy atom '${toString (atom.id or idx)}' must declare receiverScope or responderScope"
          [ "Declare receiver/responder scope explicitly." ])
        (req [ "discovery" "selectedProtocols" ] (isStringList protocols && protocols != [ ])
          "E_SHARED_SERVICE_POLICY_ATOM_DISCOVERY_PROTOCOLS"
          "shared-service discovery policy atom '${toString (atom.id or idx)}' must declare discovery selectedProtocols/protocols"
          [ "Do not infer discovery protocols from service names or renderer runtime names." ])
        (req [ "discovery" "transports" ] (builtins.isList surfaces)
          "E_SHARED_SERVICE_POLICY_ATOM_DISCOVERY_SURFACES"
          "shared-service discovery policy atom '${toString (atom.id or idx)}' must declare discovery transports as a list"
          [ "Declare protocol surfaces and ports explicitly where they are part of the source policy." ])
      ]
      true;

  normalizeAtom =
    atom:
    let
      _valid = validateAtom atom;
      discovery = atom.discovery;
      protocols = selectedProtocols discovery;
      scopes = scopeList atom;
      responder = receiverScope atom;
      deniedByDesign = discovery.doesNotAuthorize or atom.deniedByDesign or [ ];
    in
    builtins.seq _valid (
      {
        id = atom.id;
        service = atom.service;
        serviceClass = atom.serviceClass;
        requesterScopes = scopes;
        controllerScopes = scopes;
        responderScope = responder;
        receiverScope = responder;
        discovery = {
          allowed = true;
          decision = discovery.decision or null;
          protocols = protocols;
          surfaces = map normalizeSurface (rawSurfaces discovery);
          deniedByDesign = deniedByDesign;
        };
        payload = {
          authorized = false;
          inferredFromDiscovery = false;
        };
        source = {
          outputPath = [
            "accessSpaceDiscovery"
            "sharedServicePolicyAtoms"
            atom.id
          ];
          sourceClass = "user-intent";
          sourcePath = [
            "communicationContract"
            "sharedServicePolicyAtoms"
            atom._atomIndex
          ];
          authority = "network-compiler";
        };
      }
      // lib.optionalAttrs (has "sms" atom) {
        sms = atom.sms;
      }
      // lib.optionalAttrs (has "provider" atom) {
        provider = atom.provider;
      }
      // lib.optionalAttrs (has "serviceSurface" atom) {
        serviceSurface = atom.serviceSurface;
      }
      // lib.optionalAttrs (has "surface" atom) {
        serviceSurface = atom.surface;
      }
      // lib.optionalAttrs (has "deniedPaths" atom) {
        deniedPaths = atom.deniedPaths;
      }
    );

  normalized = map normalizeAtom discoveryAtoms;
  _uniqueAtoms = assertUnique "shared-service discovery policy atom id" (map (atom: atom.id) normalized);
in
builtins.seq _uniqueAtoms normalized
