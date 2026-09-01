{
  lib,
  recursiveRaw,
  coreNames,
  coreUplinks,
  helpers,
  services,
}:

let
  inherit (helpers)
    candidateId
    sortRecords
    warning
    ;
  evaluateBinding = import ./bindings/evaluate.nix {
    inherit
      lib
      coreNames
      coreUplinks
      helpers
      services
      ;
  };
  raw = if builtins.isList (recursiveRaw.bindings or null) then recursiveRaw.bindings else [ ];

  evaluations = map evaluateBinding.evaluate raw;
  missingBindingWarnings =
    if raw != [ ] || services.normalized == [ ] then
      [ ]
    else
      map (
        service:
        warning {
          code = "DNS_CORE_BINDING_MISSING";
          requester = "unbound-requester";
          resolverService = service.name;
          resolverNode = service.providerNode;
          candidateIds = map candidateId services.raw;
          context = "named-core-binding";
        }
      ) services.normalized;
in
{
  warnings = missingBindingWarnings ++ lib.concatMap (entry: entry.warnings) evaluations;
  normalized = sortRecords (
    map (entry: entry.normalized) (lib.filter (entry: entry.active) evaluations)
  );
}
