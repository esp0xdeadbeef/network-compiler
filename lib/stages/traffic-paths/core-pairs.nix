{ lib }:
{ siteKey
, throwError
, firstRole
, relation
, fromCores
, toCores
,
}:

let
  sameCoreExternalPairs =
    fromCores != [ ] && toCores != [ ] && builtins.any
      (fromCore: builtins.elem fromCore toCores)
      fromCores;

  _noExternalCoreLoop =
    if sameCoreExternalPairs then
      throwError {
        code = "E_TRAFFIC_PATH_EXTERNAL_CORE_LOOP";
        site = siteKey;
        path = [ "communicationContract" "relations" relation.source.id ];
        message = "external-to-external relation '${relation.source.id}' resolves source and destination to the same core node";
        hints = [
          "Model overlay ingress and WAN egress as distinct external uplinks on distinct core nodes."
          "For WAN egress, use external.uplinks = [ \"<uplink-name>\" ] so intent selects the desired ISP/core explicitly."
          "Do not let overlay ingress return to the same core as WAN authorization."
        ];
      }
    else
      true;
in
if _noExternalCoreLoop && fromCores != [ ] && toCores != [ ] then
  lib.concatMap
    (
      fromCore:
      map
        (toCore: {
          inherit fromCore toCore;
        })
        toCores
    )
    fromCores
else if fromCores != [ ] then
  map
    (core: {
      fromCore = core;
      toCore = core;
    })
    fromCores
else if toCores != [ ] then
  map
    (core: {
      fromCore = core;
      toCore = core;
    })
    toCores
else
  [
    {
      fromCore = firstRole "core";
      toCore = firstRole "core";
    }
  ]
