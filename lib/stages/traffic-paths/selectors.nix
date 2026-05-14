{ lib }:

siteKey: nodes: coreUplinks:

let
  util = import ../../correctness/util.nix { inherit lib; };
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
        path = [ "topology" "nodes" ];
        message = "canonical traffic path requires a ${role} node";
        hints = [ "Keep the compiler topology on access -> downstream-selector -> policy -> upstream-selector -> core." ];
      }
    else
      builtins.head names;

  uplinkNamesForCore = core: map (u: u.name) (coreUplinks.${core} or [ ]);

  coresForExternal =
    endpoint:
    let
      requested =
        if builtins.isAttrs endpoint && endpoint ? uplinks then
          endpoint.uplinks
        else if builtins.isAttrs endpoint && endpoint ? name then
          [ endpoint.name ]
        else
          [ ];
      matches =
        lib.filter (
          core:
          builtins.any (name: builtins.elem name (uplinkNamesForCore core)) requested
        ) (nodesByRole "core");
    in
    if matches == [ ] then [ (firstRole "core") ] else matches;

  accessForEndpoint =
    endpoint:
    let
      tenantName =
        if builtins.isAttrs endpoint && (endpoint.kind or null) == "tenant" then endpoint.name else null;
      matches =
        if tenantName == null then
          [ ]
        else
          lib.filter (
            name:
            builtins.any (
              attachment:
              (attachment.kind or null) == "tenant" && (attachment.name or null) == tenantName
            ) (nodes.${name}.attachments or [ ])
          ) (nodesByRole "access");
    in
    if matches == [ ] then firstRole "access" else builtins.head matches;

in
{
  inherit
    firstRole
    coresForExternal
    accessForEndpoint
    ;
}
