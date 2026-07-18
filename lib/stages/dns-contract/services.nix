{
  lib,
  recursiveRaw,
  coreNames,
  helpers,
}:

let
  inherit (helpers)
    candidateId
    nonEmptyString
    sortRecords
    warning
    ;
  raw = if builtins.isList (recursiveRaw.services or null) then recursiveRaw.services else [ ];
  candidatesByName =
    builtins.foldl'
      (
        acc: service:
        let
          name = toString (service.name or "<missing>");
        in
        acc // { ${name} = (acc.${name} or [ ]) ++ [ service ]; }
      )
      { }
      raw;

  warningsFor =
    service:
    let
      name = toString (service.name or "<missing>");
      providerNode = service.providerNode or null;
      providerValid = nonEmptyString providerNode && builtins.elem providerNode coreNames;
      staticUpstream =
        (service ? upstreamResolver) || (service ? upstreamResolvers) || (service ? forwarders);
    in
    lib.optional (!providerValid) (warning {
      code = "DNS_CORE_BINDING_INVALID";
      requester = "service:${name}";
      resolverService = name;
      resolverNode = if nonEmptyString providerNode then providerNode else null;
      candidateIds = coreNames;
      context = "provider-node";
    })
    ++ lib.optional ((service.addressAuthority or null) != "model-allocated-service-prefix") (warning {
      code = "DNS_CORE_BINDING_LITERAL";
      requester = "service:${name}";
      resolverService = name;
      resolverNode = if nonEmptyString providerNode then providerNode else null;
      candidateIds = [ (candidateId service) ];
      context = "service-address-authority";
    })
    ++ lib.optional staticUpstream (warning {
      code = "DNS_CORE_UPSTREAM_HARDCODED";
      requester = "service:${name}";
      resolverService = name;
      resolverNode = if nonEmptyString providerNode then providerNode else null;
      candidateIds = [ (candidateId service) ];
      context = "provider-bound-static-upstream";
    });

  valid =
    service:
    nonEmptyString (service.name or null)
    && nonEmptyString (service.providerNode or null)
    && builtins.elem service.providerNode coreNames
    && (service.addressAuthority or null) == "model-allocated-service-prefix";
  normalized = sortRecords (
    map
      (service: {
        name = service.name;
        providerNode = service.providerNode;
        addressAuthority = service.addressAuthority;
        trafficType = service.trafficType or "dns";
        recursionMode = service.recursionMode or "iterative";
      })
      (lib.filter valid raw)
  );
in
{
  inherit raw candidatesByName normalized;
  warnings = lib.concatMap warningsFor raw;
}
