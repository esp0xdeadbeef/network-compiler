{
  lib,
  ensure,
  assertUnique,
  buildDnsContract,
  buildTrafficTypeIndex,
  buildServiceIndex,
  validateNoLegacyExternalPolicy,
  validateIntentSourceBoundary,
  platformIndependence,
}:

{

  prepare =
    siteKey: declared: semantic: fabric:
    let
      communicationContract0 = declared.communicationContract or null;
      _hasCommunicationContract =
        ensure (communicationContract0 != null && builtins.isAttrs communicationContract0)
          {
            code = "E_CONTRACT_REQUIRED";
            site = siteKey;
            path = [ "communicationContract" ];
            message = "every site must define communicationContract";
            hints = [
              "Add communicationContract = { trafficTypes = [ ]; services = [ ]; relations = [ ]; }."
            ];
          };

      communicationContractBase = if _hasCommunicationContract then communicationContract0 else { };
      dns = buildDnsContract siteKey declared fabric.nodes fabric.coreUplinks;
      communicationContractDeclared = communicationContractBase // {
        services =
          (communicationContractBase.services or [ ]) ++ (dns.communicationContract.services or [ ]);
        relations =
          (communicationContractBase.relations or [ ]) ++ (dns.communicationContract.relations or [ ]);
      };

      tenants0 =
        if semantic ? segments && semantic.segments ? tenants then semantic.segments.tenants else [ ];
      tenants = lib.sort (a: b: a.name < b.name) tenants0;
      tenantNames = map (t: t.name) tenants;
      trafficTypeIndex = buildTrafficTypeIndex communicationContractDeclared;

      # FS-210/FS-230: the compiler owns endpoint and service ownership. Resolve
      # each service provider endpoint to the tenant that owns it so every
      # downstream layer can bind the ingress target to its provider tenant
      # (and thus to the provider's access) without re-reading raw intent.
      endpointTenantByName =
        builtins.listToAttrs (
          map
            (endpoint: {
              name = endpoint.name;
              value = endpoint.tenant;
            })
            (lib.filter
              (endpoint: builtins.isAttrs endpoint && endpoint.name != null && endpoint.tenant != null)
              ((declared.ownership or { }).endpoints or [ ])
            )
        );
      resolveProviderTenant =
        provider:
        endpointTenantByName.${provider} or null;
      serviceWithProviderTenants =
        service:
        let
          providers = if builtins.isList (service.providers or null) then service.providers else [ ];
          providerTenants = lib.unique (
            lib.filter (t: t != null) (map resolveProviderTenant providers)
          );
        in
        service // { inherit providerTenants; };
      serviceIndex =
        builtins.mapAttrs (_name: service: serviceWithProviderTenants service)
          (buildServiceIndex communicationContractDeclared);
    in
    {
      inherit
        communicationContractBase
        communicationContractDeclared
        dns
        tenants
        tenantNames
        trafficTypeIndex
        serviceIndex
        ;
      validations = {
        inherit _hasCommunicationContract;
        _noLegacyExternalPolicy = validateNoLegacyExternalPolicy siteKey declared;
        _intentSourceBoundary = validateIntentSourceBoundary siteKey declared;
        _platformIndependentIntent = platformIndependence.validateIntent siteKey declared;
        _uniqTenants = assertUnique "tenant name" tenantNames;
        _uniqTrafficTypes = assertUnique "traffic type name" (builtins.attrNames trafficTypeIndex);
        _uniqServices = assertUnique "service name" (builtins.attrNames serviceIndex);
      };
    };
}
