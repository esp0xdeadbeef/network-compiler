{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;
  has = attr: attrs: builtins.isAttrs attrs && builtins.hasAttr attr attrs;

  requireAttr =
    siteKey: serviceName: path: attrs: attr:
    ensure (has attr attrs) {
      code = "E_SERVICE_POLICY_REQUIRED_FIELD";
      site = siteKey;
      path = [
        "communicationContract"
        "services"
        serviceName
        "servicePolicy"
      ] ++ path ++ [ attr ];
      message = "service '${serviceName}' servicePolicy is missing required field '${lib.concatStringsSep "." (path ++ [ attr ])}'";
      hints = [
        "Declare discovery, payload, management, reverseInitiation, deniedPaths, exposureClass, authenticationBoundary, and cloudDependency explicitly for shared service policies."
      ];
    };

  forbidTrue =
    siteKey: serviceName: field: policy:
    ensure (!(has field policy && policy.${field} == true)) {
      code = "E_SERVICE_POLICY_INFERRED_AUTHORITY";
      site = siteKey;
      path = [
        "communicationContract"
        "services"
        serviceName
        "servicePolicy"
        field
      ];
      message = "service '${serviceName}' servicePolicy must not infer authority from '${field}'";
      hints = [
        "Model discovery, payload, management, reverse-initiation, denied paths, exposure, authentication, and cloud dependency as separate explicit fields."
        "Do not derive client, tenant, resolver, discovery, management, payload, or reverse-initiation authority from underlay reachability, host placement, or service existence."
      ];
    };

  normalizeServicePolicy =
    siteKey: serviceName: policy:
    let
      forbiddenInferenceFields = [
        "underlayAuthority"
        "inferClientPathAuthority"
        "inferClientPaths"
        "inferDiscoveryFromPayload"
        "inferDiscoveryFromServiceExistence"
        "inferReverseInitiation"
        "inferReverseInitiationFromPayload"
        "inferExposureFromHostPlacement"
        "inferDeniedPathsFromPayload"
      ];

      _required =
        builtins.deepSeq
          [
            (requireAttr siteKey serviceName [ ] policy "requesterScopes")
            (requireAttr siteKey serviceName [ ] policy "responderScope")
            (requireAttr siteKey serviceName [ ] policy "serviceClass")
            (requireAttr siteKey serviceName [ ] policy "discovery")
            (requireAttr siteKey serviceName [ "discovery" ] policy.discovery "protocol")
            (requireAttr siteKey serviceName [ "discovery" ] policy.discovery "direction")
            (requireAttr siteKey serviceName [ "discovery" ] policy.discovery "advertisedServices")
            (requireAttr siteKey serviceName [ ] policy "payload")
            (requireAttr siteKey serviceName [ "payload" ] policy.payload "protocol")
            (requireAttr siteKey serviceName [ "payload" ] policy.payload "ports")
            (requireAttr siteKey serviceName [ "payload" ] policy.payload "direction")
            (requireAttr siteKey serviceName [ "payload" ] policy.payload "returnBehavior")
            (requireAttr siteKey serviceName [ ] policy "management")
            (requireAttr siteKey serviceName [ ] policy "reverseInitiation")
            (requireAttr siteKey serviceName [ ] policy "deniedPaths")
            (requireAttr siteKey serviceName [ ] policy "exposureClass")
            (requireAttr siteKey serviceName [ ] policy "authenticationBoundary")
            (requireAttr siteKey serviceName [ ] policy "cloudDependency")
          ]
          true;

      _noInference =
        builtins.deepSeq
          (map (field: forbidTrue siteKey serviceName field policy) forbiddenInferenceFields)
          true;

      # FS-610-HDS-010-SDS-010-SMS-020: discovery boundary decision separation with specific diagnostics
      requireDiscoveryBoundaryDecision =
        import ./discovery-boundary-decision.nix { inherit lib; };

      _discoveryBoundaryDecision =
        builtins.deepSeq
          [
            (requireDiscoveryBoundaryDecision siteKey serviceName policy)
          ]
          true;

      # FS-620-HDS-010-SDS-010-SMS-030: underlay authority rejection with specific diagnostics
      requireNoUnderlayAuthority =
        import ./underlay-authority.nix { inherit lib; };

      _underlayAuthorityBoundary =
        builtins.deepSeq
          [
            (requireNoUnderlayAuthority siteKey serviceName policy)
          ]
          true;

      requireManagementAccessPolicy =
        siteKey: serviceName: policy:
        ensure (!(has "management" policy && policy.management.allowed or false == true && !(has "managementAccessPolicy" policy))) {
          code = "MANAGEMENT_INFERRED_FROM_PAYLOAD";
          site = siteKey;
          path = [
            "communicationContract"
            "services"
            serviceName
            "servicePolicy"
            "management"
          ];
          message = "service '${serviceName}' management.allowed is true but no explicit managementAccessPolicy record; management reachability must be explicitly modeled, not inferred from discovery, payload, or reverse initiation";
          hints = [
            "Add a managementAccessPolicy field to the service policy to explicitly authorize management access."
          ];
        };

      requireManagementDeniedPath =
        siteKey: serviceName: policy:
        ensure (!(has "management" policy && policy.management.allowed or true == false && (!(has "deniedPaths" policy) || builtins.length (policy.deniedPaths or [ ]) == 0))) {
          code = "MISSING_DENIED_PATH_DATA";
          site = siteKey;
          path = [
            "communicationContract"
            "services"
            serviceName
            "servicePolicy"
          ];
          message = "service '${serviceName}' management reachability is denied but denied-path data for the media-to-management path is absent";
          hints = [
            "Add a deniedPath record for the media service capturing the media-to-management denial evidence."
          ];
        };

      _managementBoundary =
        builtins.deepSeq
          [
            (requireManagementAccessPolicy siteKey serviceName policy)
            (requireManagementDeniedPath siteKey serviceName policy)
          ]
          true;

      # FS-630-HDS-010-SDS-010-SMS-040: denied-path preservation boundary
      requireNonEmptyDeniedPaths =
        import ./denied-path-boundary.nix { inherit lib; };

      _deniedPathBoundary =
        builtins.deepSeq
          [
            (requireNonEmptyDeniedPaths siteKey serviceName policy)
          ]
          true;
      # FS-640-HDS-010-SDS-010-SMS-020: media payload authorization with specific diagnostics
      requireMediaPayloadAuth =
        import ./media-payload-authorization.nix { inherit lib; };

      _mediaPayloadAuthBoundary =
        builtins.deepSeq
          [
            (requireMediaPayloadAuth siteKey serviceName policy)
          ]
          true;
    in
    builtins.seq _mediaPayloadAuthBoundary (
    builtins.seq _required (
      builtins.seq _discoveryBoundaryDecision (
      builtins.seq _noInference (
        builtins.seq _underlayAuthorityBoundary (
        builtins.seq _managementBoundary (
        builtins.seq _deniedPathBoundary {
        requesterScopes = policy.requesterScopes;
        responderScope = policy.responderScope;
        serviceClass = policy.serviceClass;
        discovery = policy.discovery;
        payload = policy.payload;
        management = policy.management;
        managementAccessPolicy = policy.managementAccessPolicy or null;
        reverseInitiation = policy.reverseInitiation;
        deniedPaths = policy.deniedPaths;
        exposureClass = policy.exposureClass;
        authenticationBoundary = policy.authenticationBoundary;
        cloudDependency = policy.cloudDependency;
      }
    )
    )
    )
    )
    )
  );
in
siteKey: serviceIndex: serviceNames:
map
  (
    name:
    let
      svc = serviceIndex.${name};
      servicePolicy =
        if builtins.isAttrs (svc.servicePolicy or null) then
          normalizeServicePolicy siteKey name svc.servicePolicy
        else
          null;
    in
    {
      name = svc.name;
      trafficType = svc.trafficType or "any";
      providers = svc.providers or [ ];
    }
    // lib.optionalAttrs (servicePolicy != null) servicePolicy
  )
  (lib.sort builtins.lessThan serviceNames)
