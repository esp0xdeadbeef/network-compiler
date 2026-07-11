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

  forbiddenInferenceFields = [
    "underlayAuthority"
    "inferClientPathAuthority"
    "inferClientPaths"
    "inferDiscoveryFromPayload"
    "inferDiscoveryFromServiceExistence"
    "inferDiscoveryFromDnsRecord"
    "inferDiscoveryFromHostPlacement"
    "inferReverseInitiation"
    "inferReverseInitiationFromPayload"
    "inferExposureFromHostPlacement"
    "inferDeniedPathsFromPayload"
  ];
in
{
  validateRequired =
    siteKey: serviceName: policy:
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

  validateNoInference =
    siteKey: serviceName: policy:
    builtins.deepSeq
      (map (field: forbidTrue siteKey serviceName field policy) forbiddenInferenceFields)
      true;
}
