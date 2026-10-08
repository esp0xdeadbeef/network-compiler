# Canonical stage-role and core-selection resolution, split out of
# traffic-paths/selectors.nix so the selector module stays under the tracked LOC
# soft limit.
{ lib }:

siteKey: nodes: coreUplinks:
{
  overlays ? [ ],
}:

let
  util = import ../../../correctness/util.nix { inherit lib; };
  inherit (util) throwError;

  nodeNames = lib.sort builtins.lessThan (builtins.attrNames nodes);
  nodesByRole = role: lib.filter (name: (nodes.${name}.role or null) == role) nodeNames;

  firstRole =
    role:
    let
      names = nodesByRole role;
    in
    if names == [ ] then
      throwError {
        code = "E_TRAFFIC_PATH_STAGE_MISSING";
        site = siteKey;
        path = [
          "topology"
          "nodes"
        ];
        message = "canonical traffic path requires a ${role} node";
        hints = [
          "Keep the compiler topology on access -> downstream-selector -> policy -> upstream-selector -> core."
        ];
      }
    else
      builtins.head names;

  accessNodes =
    let
      names = nodesByRole "access";
    in
    if names == [ ] then [ (firstRole "access") ] else names;

  uplinkNamesForCore = core: map (u: u.name) (coreUplinks.${core} or [ ]);

  selectsOf =
    nodeName:
    map (
      s:
      if builtins.isString s then
        s
      else if builtins.isAttrs s then
        (s.scope or s.uplink or null)
      else
        null
    ) (nodes.${nodeName}.selects or [ ]);

  coresForSelection =
    selection:
    let
      deterministic = lib.sort builtins.lessThan (
        lib.filter (core: core == selection || builtins.elem selection (uplinkNamesForCore core)) (
          nodesByRole "core"
        )
      );
    in
    if deterministic != [ ] then deterministic else [ selection ];

  coresForExternal =
    endpoint:
    let
      requested =
        if builtins.isAttrs endpoint && endpoint ? scope then
          [ endpoint.scope ]
        else if builtins.isAttrs endpoint && endpoint ? name then
          [ endpoint.name ]
        else
          [ ];
      matches = lib.filter (
        core: builtins.any (name: name == core || builtins.elem name (uplinkNamesForCore core)) requested
      ) (nodesByRole "core");

      overlayTerminators = lib.unique (
        builtins.concatLists (
          map (
            o:
            let
              t = o.terminateOn or null;
            in
            if (o.name or null) != null && builtins.elem (o.name or null) requested then
              (
                if builtins.isList t then
                  t
                else if t == null then
                  [ ]
                else
                  [ t ]
              )
            else
              [ ]
          ) overlays
        )
      );
    in
    if overlayTerminators != [ ] then
      overlayTerminators
    else if matches == [ ] then
      [ (firstRole "core") ]
    else
      matches;
in
{
  inherit
    nodeNames
    nodesByRole
    firstRole
    accessNodes
    uplinkNamesForCore
    selectsOf
    coresForSelection
    coresForExternal
    ;
}
