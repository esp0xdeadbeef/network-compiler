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
      serviceIndex = buildServiceIndex communicationContractDeclared;
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
