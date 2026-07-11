{ lib }:

let
  policyFields = import ./compiled-services-policy-fields.nix { inherit lib; };

  normalizeServicePolicy =
    siteKey: serviceName: policy:
    let
      _required =
        policyFields.validateRequired siteKey serviceName policy;

      _noInference =
        policyFields.validateNoInference siteKey serviceName policy;

      # FS-590-HDS-010-SDS-010-SMS-040: discovery authority inference denial with specific diagnostics
      requireDiscoveryAuthorityInferenceDenial =
        import ./discovery-authority-inference-denial.nix { inherit lib; };

      _discoveryAuthorityInferenceDenial =
        builtins.deepSeq
          [
            (requireDiscoveryAuthorityInferenceDenial siteKey serviceName policy)
          ]
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

      requireManagementBoundary =
        import ./compiled-services-management-boundary.nix { inherit lib; };

      _managementBoundary =
        builtins.deepSeq
          [
            (requireManagementBoundary siteKey serviceName policy)
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

      # FS-640-HDS-010-SDS-010-SMS-050: media denied-path preservation with specific diagnostics
      requireMediaDeniedPathPreservation =
        import ./media-denied-path-preservation.nix { inherit lib; };

      _mediaDeniedPathPreservationBoundary =
        builtins.deepSeq
          [
            (requireMediaDeniedPathPreservation siteKey serviceName policy)
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
      # FS-630-HDS-010-SDS-010-SMS-020: printer payload authorization with specific diagnostics
      requirePrinterPayloadAuth =
        import ./printer-payload-authorization.nix { inherit lib; };

      _printerPayloadAuthBoundary =
        builtins.deepSeq
          [
            (requirePrinterPayloadAuth siteKey serviceName policy)
          ]
          true;
    in
    builtins.seq _printerPayloadAuthBoundary (
    builtins.seq _mediaPayloadAuthBoundary (
    builtins.seq _managementBoundary (
    builtins.seq _mediaDeniedPathPreservationBoundary (
    builtins.seq _required (
      builtins.seq _discoveryBoundaryDecision (
      builtins.seq _discoveryAuthorityInferenceDenial (
      builtins.seq _noInference (
        builtins.seq _underlayAuthorityBoundary (
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
