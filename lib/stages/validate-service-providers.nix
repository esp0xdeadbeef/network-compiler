{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;

in
siteKey: serviceIndex: semantic: nodes: relations:

let
  serviceNames = builtins.attrNames serviceIndex;
  hostNames = lib.sort builtins.lessThan (map (host: host.name) (semantic.hosts or [ ]));
  serviceProviderNames = lib.sort builtins.lessThan (
    map (provider: provider.name) (semantic.serviceProviderEndpoints or [ ])
  );
  nodeNames = lib.sort builtins.lessThan (builtins.attrNames nodes);
  localProviderNames = lib.unique (hostNames ++ serviceProviderNames ++ nodeNames);

  relationTargetsService =
    serviceName:
    lib.filter (
      relation:
      builtins.isAttrs relation
      && builtins.isAttrs (relation.to or null)
      && (relation.to.kind or null) == "service"
      && (relation.to.name or null) == serviceName
    ) relations;

  serviceIsExternalIngressOnly =
    serviceName:
    let
      targetRelations = relationTargetsService serviceName;
    in
    targetRelations != [ ]
    && builtins.all (
      relation: builtins.isAttrs (relation.from or null) && (relation.from.kind or null) == "external"
    ) targetRelations;

in
builtins.all (
  serviceName:
  let
    service = serviceIndex.${serviceName};
    providers = if builtins.isList (service.providers or null) then service.providers else [ ];
    missing = lib.filter (provider: !(builtins.elem provider localProviderNames)) providers;
    nodeProviderValid =
      (service.providerNode or null) == null
      || (
        builtins.elem service.providerNode nodeNames
        && ((nodes.${service.providerNode}.role or null) == "core")
      );
  in
  ensure ((missing == [ ] || serviceIsExternalIngressOnly serviceName) && nodeProviderValid) {
    code = "E_CONTRACT_UNKNOWN_SERVICE_PROVIDER";
    site = siteKey;
    path = [
      "communicationContract"
      "services"
      serviceName
      "providers"
    ];
    message = "service '${serviceName}' references provider(s) not declared as local ownership endpoints/core nodes, or names a non-core providerNode: ${lib.concatStringsSep ", " missing}";
    hints = [
      "Declare each provider under ownership.endpoints for this site."
      "Remote providers are only valid for services reached exclusively from external ingress relations."
      "For tenant-origin cross-site DNS or service access, model the destination as overlay/external reachability to the remote site instead of a local service alias."
    ];
  }
) serviceNames
