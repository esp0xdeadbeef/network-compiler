# FS-322 / FS-481: contract scope selection and routing-behavior normalization,
# split out of build-model/fabric.nix so the fabric assembly module stays under
# the tracked LOC soft limit.
{
  lib,
  siteKey,
  nodes,
  coreUplinks,
  coreNodes,
  normalizeUplinksForNode,
  coreUplinkOwner,
}:

let
  util = import ../../../correctness/util.nix { inherit lib; };
  inherit (util) throwError;

  selectionTarget =
    nodeName: entry:
    let
      name =
        if builtins.isString entry then
          entry
        else if builtins.isAttrs entry then
          (entry.scope or entry.uplink or null)
        else
          null;
      owner = if name != null then coreUplinkOwner name else null;
      target = if owner != null then owner else name;

      surface = name;
    in
    if name == null then
      throwError {
        code = "E_CONTRACT_SELECTS";
        site = siteKey;
        path = [
          "topology"
          "nodes"
          nodeName
          "selects"
        ];
        message = "selects entries must name a scope (FS-322 Scope Reachability; owning item: FS-322).";
        spec = "FS-322 Scope Reachability; owning item: FS-322";
        hints = [ "Give each selects entry a scope string, for example selects = [ \"<exit-scope>\" ]." ];
      }
    else if !(builtins.hasAttr target nodes) then
      throwError {
        code = "E_CONTRACT_UNKNOWN_SELECT";
        site = siteKey;
        path = [
          "topology"
          "nodes"
          nodeName
          "selects"
        ];
        message = "topology.nodes.${nodeName}.selects names '${target}', which is not a modeled scope (FS-322 Scope Reachability; owning item: FS-322).";
        spec = "FS-322 Scope Reachability; owning item: FS-322";
        hints = [
          "Declare the scope under topology.nodes.<name>, or name an uplink a modeled scope owns."
        ];
      }
    else
      { inherit target surface; };

  normalizeSelects =
    nodeName: node:
    let
      raw = node.selects or [ ];
    in
    if !(builtins.isList raw) then
      throwError {
        code = "E_CONTRACT_SELECTS";
        site = siteKey;
        path = [
          "topology"
          "nodes"
          nodeName
          "selects"
        ];
        message = "topology.nodes.${nodeName}.selects must be a list (FS-322 Scope Reachability; owning item: FS-322).";
        spec = "FS-322 Scope Reachability; owning item: FS-322";
        hints = [ "Declare selects as a list of scope names." ];
      }
    else
      map (
        entry:
        let
          resolved = selectionTarget nodeName entry;
          target = resolved.target;
          surface = resolved.surface;
          behaviors =
            if builtins.isAttrs entry then
              if builtins.isList (entry.behaviors or null) then
                entry.behaviors
              else
                throwError {
                  code = "E_CONTRACT_SELECTS";
                  site = siteKey;
                  path = [
                    "topology"
                    "nodes"
                    nodeName
                    "selects"
                  ];
                  message = "topology.nodes.${nodeName}.selects[] behaviors must be a list (FS-481 Routing Behavior Selection).";
                  spec = "FS-481 Routing Behavior Selection";
                  hints = [ "Declare behaviors as a list of required behavior names." ];
                }
            else
              [ ];
        in
        {
          scope = target;
          surface = surface;
          inherit behaviors;
        }
      ) raw;
in
let
  behaviorsMod = import ./contract-behaviors.nix {
    inherit lib siteKey nodes coreUplinkOwner normalizeUplinksForNode;
  };
in
{
  inherit
    selectionTarget
    normalizeSelects
    ;
  inherit (behaviorsMod)
    recognizedBehaviors
    allBehaviorsOf
    validateBehaviors
    ;
}
