{ lib }:
{
  siteKey,
  throwError,
  firstRole,
  relation,
  fromCores,
  toCores,
}:

let
  bothEndpointsExternal =
    builtins.isAttrs (relation.from or null)
    && (relation.from.kind or null) == "external"
    && builtins.isAttrs (relation.to or null)
    && (relation.to.kind or null) == "external";

  sameCoreExternalPairs =
    bothEndpointsExternal
    && fromCores != [ ]
    && toCores != [ ]
    && builtins.any (fromCore: builtins.elem fromCore toCores) fromCores;

  _noExternalCoreLoop =
    if sameCoreExternalPairs then
      throwError {
        code = "E_TRAFFIC_PATH_EXTERNAL_CORE_LOOP";
        site = siteKey;
        path = [
          "communicationContract"
          "relations"
          relation.source.id
        ];
        message = "external-to-external relation '${relation.source.id}' resolves source and destination to the same core node";
        hints = [
          "Model overlay ingress and WAN egress as distinct external scopes on distinct core nodes."
          "For egress, name the exit scope with external.scope = \"<exit-scope>\" and declare the selection with the scope's 'selects'."
          "Do not let overlay ingress return to the same core as egress authorization."
        ];
      }
    else
      true;
in
if _noExternalCoreLoop && fromCores != [ ] && toCores != [ ] then
  lib.concatMap (
    fromCore:
    map (toCore: {
      inherit fromCore toCore;
    }) toCores
  ) fromCores
else if fromCores != [ ] then
  map (core: {
    fromCore = core;
    toCore = core;
  }) fromCores
else if toCores != [ ] then
  map (core: {
    fromCore = core;
    toCore = core;
  }) toCores
else if
  # A bare `{ kind = "external"; }` names no scope, no overlay and no uplinks,
  # so nothing can select it. FS-323-HDS-010-SDS-010 accepts a reachability fact
  # only from a scope's `offers` and `selects`, so such a relation contributes no
  # path: with every `selects` stripped from the single-wan fixture,
  # `allow-tenants-to-wan` was handed a five-hop path through `firstRole "core"`
  # purely because its permit relation existed.
  #
  # A wildcard (`to = "any"`) and any destination that does name a scope keep the
  # canonical primary-core pair below; those are reachability the model does
  # carry, and the four cases that assert them still pass.
  builtins.isAttrs (relation.to or null)
  && (relation.to.kind or null) == "external"
  && !(relation.to ? scope)
  && !(relation.to ? name)
  && !(relation.to ? uplinks)
then
  [ ]
else
  [
    {
      fromCore = firstRole "core";
      toCore = firstRole "core";
    }
  ]
