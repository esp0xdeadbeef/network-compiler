{ lib }:

siteKey: nodes: tenants: hosts: compiledServices: communicationContract:
let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;
  has = attr: attrs: builtins.isAttrs attrs && builtins.hasAttr attr attrs;
  basePath = idx: extra: [ "communicationContract" "isolationDecisions" idx ] ++ extra;
  require =
    cond: code: idx: extra: message: hints:
    ensure cond {
      inherit code siteKey;
      site = siteKey;
      path = basePath idx extra;
      inherit message hints;
    };

  accessNames = lib.sort builtins.lessThan (
    lib.filter (name: (nodes.${name}.role or null) == "access") (builtins.attrNames nodes)
  );
  tenantNames = map (tenant: tenant.name) tenants;
  clientNames = map (host: host.name) hosts;
  tenantAccess =
    lib.concatMap
      (access:
        map (attachment: { inherit access; tenant = attachment.name; })
          (lib.filter
            (attachment: builtins.isAttrs attachment && (attachment.kind or null) == "tenant")
            (nodes.${access}.attachments or [ ])))
      accessNames;
  clientIdentities =
    map
      (host: {
        client = host.name;
        tenant = host.tenant;
        access = map (entry: entry.access) (lib.filter (entry: entry.tenant == host.tenant) tenantAccess);
      })
      hosts;
  sharedServiceRelationships =
    map
      (service: {
        service = service.name;
        providers = service.providers or [ ];
        requesterScopes = service.requesterScopes or [ ];
        responderScope = service.responderScope or null;
        payload = service.payload or null;
        discovery = service.discovery or null;
        deniedPaths = service.deniedPaths or [ ];
      })
      (lib.filter (service: has "requesterScopes" service && has "responderScope" service) compiledServices);
  decisions = communicationContract.isolationDecisions or [ ];
  requireField =
    idx: decision: field:
    require (has field decision) "E_ISOLATION_DECISION_REQUIRED_FIELD" idx [ field ]
      "isolation decision ${toString idx} is missing required field '${field}'"
      [ "Declare id, scope, classification, from, to, and boundary for every isolation decision." ];
  validateEndpoint =
    import ./isolation-endpoint.nix { inherit lib; } {
      inherit siteKey tenantNames accessNames clientNames ensure basePath;
    };
  normalizeDecision =
    idx: decision:
    let
      _required = builtins.deepSeq [
        (requireField idx decision "id")
        (requireField idx decision "scope")
        (requireField idx decision "classification")
        (requireField idx decision "from")
        (requireField idx decision "to")
        (requireField idx decision "boundary")
      ] true;

      scope = decision.scope;
      classification = decision.classification;
      serviceLimits = decision.serviceLimits or [ ];
      _scope =
        require (builtins.elem scope [ "intra-access" "intra-tenant" ])
          "E_ISOLATION_DECISION_SCOPE" idx [ "scope" ]
          "isolation decision scope must be intra-access or intra-tenant"
          [ "Classify only the FS-620 SMS-010 isolation scopes at the compiler layer." ];
      _classification =
        require (builtins.elem classification [ "allowed" "denied" "service-limited" ])
          "E_ISOLATION_DECISION_CLASSIFICATION" idx [ "classification" ]
          "isolation decision classification must be allowed, denied, or service-limited"
          [ "Do not leave same-access or same-tenant reachability implicit." ];
      _boundary =
        require (builtins.isString decision.boundary && decision.boundary != "")
          "E_ISOLATION_BOUNDARY_REQUIRED" idx [ "boundary" ]
          "isolation decision requires a named isolation boundary"
          [ "Name the policy, access, or tenant boundary that owns this classification." ];
      namedLimits = builtins.isList serviceLimits && serviceLimits != [ ]
        && builtins.all (limit: builtins.isString limit && limit != "") serviceLimits;
      _serviceLimits =
        require (classification != "service-limited" || namedLimits)
          "E_ISOLATION_SERVICE_LIMITS_REQUIRED" idx [ "serviceLimits" ]
          "service-limited isolation decision requires named service limits"
          [ "List the exact services, protocols, or payload limits that make this row service-limited." ];
    in
    builtins.seq _required (
      builtins.seq _scope (
        builtins.seq _classification (
          builtins.seq _boundary (
            builtins.seq _serviceLimits {
              id = decision.id;
              inherit scope classification serviceLimits;
              from = validateEndpoint idx "from" decision.from;
              to = validateEndpoint idx "to" decision.to;
              boundary = decision.boundary;
              source = {
                outputPath = [ "isolationDecisions" idx ];
                sourceClass = "user-intent";
                sourcePath = [ "communicationContract" "isolationDecisions" idx ];
                authority = "network-compiler";
              };
              relationshipInputs = {
                relationIds = decision.relationIds or [ ];
                serviceNames = decision.serviceNames or [ ];
                trafficTypes = decision.trafficTypes or [ ];
              };
            }
          )
        )
      )
    );
in
{
  consumedInterfaces = {
    tenants = tenants;
    access = tenantAccess;
    clients = clientIdentities;
    sharedServices = sharedServiceRelationships;
  };
  isolationDecisions = lib.imap0 normalizeDecision decisions;
}
