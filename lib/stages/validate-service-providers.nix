{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) ensure;

in
siteKey: serviceIndex: semantic: relations:

let
  serviceNames = builtins.attrNames serviceIndex;
  hostNames = lib.sort builtins.lessThan (map (host: host.name) (semantic.hosts or [ ]));

  relationTargetsService =
    serviceName:
    lib.filter
      (
        relation:
        builtins.isAttrs relation
        && builtins.isAttrs (relation.to or null)
        && (relation.to.kind or null) == "service"
        && (relation.to.name or null) == serviceName
      )
      relations;

  serviceIsExternalIngressOnly =
    serviceName:
    let
      targetRelations = relationTargetsService serviceName;
    in
    targetRelations != [ ]
    && builtins.all
      (
        relation:
        builtins.isAttrs (relation.from or null) && (relation.from.kind or null) == "external"
      )
      targetRelations;

in
builtins.all
  (
    serviceName:
    let
      service = serviceIndex.${serviceName};
      providers = if builtins.isList (service.providers or null) then service.providers else [ ];
      missing = lib.filter (provider: !(builtins.elem provider hostNames)) providers;
    in
    ensure (missing == [ ] || serviceIsExternalIngressOnly serviceName) {
      code = "E_CONTRACT_UNKNOWN_SERVICE_PROVIDER";
      site = siteKey;
      path = [
        "communicationContract"
        "services"
        serviceName
        "providers"
      ];
      message = "service '${serviceName}' references provider(s) not declared as local ownership endpoints and is not restricted to external ingress: ${lib.concatStringsSep ", " missing}";
      hints = [
        "Declare each provider under ownership.endpoints for this site."
        "Remote providers are only valid for services reached exclusively from external ingress relations."
        "For tenant-origin cross-site DNS or service access, model the destination as overlay/external reachability to the remote site instead of a local service alias."
      ];
    }
  )
  serviceNames
