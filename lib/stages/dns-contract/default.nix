{ lib }:

siteKey: declared: nodes: coreUplinks:

let
  recursiveRaw =
    if builtins.isAttrs (declared.recursiveDnsIntent or null) then
      declared.recursiveDnsIntent
    else
      { };
  localRaw =
    if builtins.isAttrs (declared.localDnsSharingIntent or null) then
      declared.localDnsSharingIntent
    else
      null;
  nodeNames = lib.sort builtins.lessThan (builtins.attrNames nodes);
  coreNames = lib.filter (name: (nodes.${name}.role or null) == "core") nodeNames;

  helpers = import ./warnings.nix {
    inherit lib siteKey declared;
  };
  services = import ./services.nix {
    inherit lib recursiveRaw coreNames helpers;
  };
  bindings = import ./bindings.nix {
    inherit
      lib
      recursiveRaw
      coreNames
      coreUplinks
      helpers
      services
      ;
  };
  localSharing = import ./local-sharing.nix {
    inherit lib localRaw helpers;
  };

  allWarnings = helpers.sortRecords (
    services.warnings ++ bindings.warnings ++ localSharing.warnings
  );
  fatalWarnings = lib.filter (entry: entry.code != "DNS_CORE_UPSTREAM_HARDCODED") allWarnings;
  recursiveRelations =
    if fatalWarnings == [ ] && builtins.isList (recursiveRaw.relations or null) then
      helpers.sortRecords recursiveRaw.relations
    else
      [ ];
  communicationServices =
    if fatalWarnings != [ ] then
      [ ]
    else
      map
        (service: {
          inherit (service)
            name
            trafficType
            providerNode
            addressAuthority
            recursionMode
            ;
          providers = [ service.providerNode ];
          providerRole = "core";
        })
        services.normalized;
in
{
  schemaVersion = 1;
  recursive = {
    services = services.normalized;
    relations = recursiveRelations;
    bindings = bindings.normalized;
  };
  localSharing = localSharing.normalized;
  warnings = allWarnings;
  communicationContract = {
    services = communicationServices;
    relations = recursiveRelations;
  };
}
