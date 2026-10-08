# FS-481: routing-behavior selection validation, split out of
# build-model/fabric/contract-selects.nix so that module stays under the tracked
# LOC soft limit.
{
  lib,
  siteKey,
  nodes,
  coreUplinkOwner,
  normalizeUplinksForNode,
}:

let
  util = import ../../../correctness/util.nix { inherit lib; };
  inherit (util) throwError;

  recognizedBehaviors = [
    "bgp"
    "liveness"
    "equal-cost-multipath"
  ];

  selectedTargetsOf =
    node:
    lib.unique (
      map (
        entry:
        let
          raw =
            if builtins.isString entry then
              entry
            else if builtins.isAttrs entry then
              (entry.surface or entry.scope or entry.uplink or null)
            else
              null;
          owner = if raw != null then coreUplinkOwner raw else null;
        in
        if owner != null then owner else raw
      ) (node.selects or [ ])
    );

  allBehaviorsOf =
    node:
    let
      nodeLevel = if builtins.isList (node.behaviors or null) then node.behaviors else [ ];
      perEntry = lib.concatMap (
        entry:
        if builtins.isAttrs entry && builtins.isList (entry.behaviors or null) then entry.behaviors else [ ]
      ) (node.selects or [ ]);
    in
    lib.unique (nodeLevel ++ perEntry);

  buildCoreUplink4 =
    nodeName:
    lib.concatMap (u: u.ipv4 or [ ]) (
      builtins.attrValues (
        normalizeUplinksForNode.forNodeAttrs siteKey nodeName (nodes.${nodeName}.uplinks or null)
      )
    );

  validateBehaviors =
    nodeName: node:
    let
      behaviors = allBehaviorsOf node;
      selection = selectedTargetsOf node;
      unknown = lib.filter (b: !(builtins.elem b recognizedBehaviors)) behaviors;

      offersBySelected = lib.concatMap (
        t: if builtins.hasAttr t nodes then [ (buildCoreUplink4 t) ] else [ ]
      ) selection;
      sharedPrefix =
        builtins.length (
          builtins.filter (
            p: builtins.length (builtins.filter (lst: builtins.elem p lst) offersBySelected) > 1
          ) (lib.unique (lib.concatLists offersBySelected))
        ) > 0;
      _unknown =
        if unknown == [ ] then
          true
        else
          throwError {
            code = "E_CONTRACT_BEHAVIOR";
            site = siteKey;
            path = [
              "topology"
              "nodes"
              nodeName
              "behaviors"
            ];
            message = "topology.nodes.${nodeName} requires unrecognized routing behavior(s) ${builtins.concatStringsSep ", " unknown} (FS-481 Routing Behavior Selection).";
            spec = "FS-481 Routing Behavior Selection; owning item: FS-481";
            hints = [ "Use one of: ${builtins.concatStringsSep ", " recognizedBehaviors}." ];
          };
      _empty =
        if behaviors == [ ] || selection != [ ] then
          true
        else
          throwError {
            code = "E_CONTRACT_BEHAVIOR";
            site = siteKey;
            path = [
              "topology"
              "nodes"
              nodeName
              "behaviors"
            ];
            message = "topology.nodes.${nodeName} requires routing behavior(s) with an empty selection (FS-481 Routing Behavior Selection).";
            spec = "FS-481 Routing Behavior Selection; owning item: FS-481";
            hints = [ "Declare at least one selected scope, or remove the behavior." ];
          };
      _ecmpOverlap =
        if !(builtins.elem "equal-cost-multipath" behaviors) then
          true
        else if sharedPrefix then
          true
        else
          throwError {
            code = "E_CONTRACT_BEHAVIOR";
            site = siteKey;
            path = [
              "topology"
              "nodes"
              nodeName
              "behaviors"
            ];
            message = "topology.nodes.${nodeName} requires equal-cost multipath but the selected scopes share no offered prefix (FS-481 Routing Behavior Selection).";
            spec = "FS-481 Routing Behavior Selection; owning item: FS-481";
            hints = [ "Select scopes that offer an overlapping prefix, or remove 'equal-cost-multipath'." ];
          };
    in
    builtins.seq _unknown (builtins.seq _empty (builtins.seq _ecmpOverlap behaviors));
in
{
  inherit
    recognizedBehaviors
    allBehaviorsOf
    validateBehaviors
    ;
}
