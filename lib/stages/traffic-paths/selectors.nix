{ lib }:

siteKey: nodes: coreUplinks: serviceIndex: hosts:

let
  util = import ../../correctness/util.nix { inherit lib; };
  inherit (util) throwError;

  nodeNames = lib.sort builtins.lessThan (builtins.attrNames nodes);
  nodesByRole = role: lib.filter (name: (nodes.${name}.role or null) == role) nodeNames;
  accessNodes =
    let
      names = nodesByRole "access";
    in
    if names == [ ] then [ (firstRole "access") ] else names;

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
      matches = lib.filter (
        core: builtins.any (name: builtins.elem name (uplinkNamesForCore core)) requested
      ) (nodesByRole "core");
    in
    if matches == [ ] then [ (firstRole "core") ] else matches;

  coresForEndpoint =
    endpoint:
    if
      builtins.isAttrs endpoint
      && (endpoint.kind or null) == "service"
      && builtins.hasAttr (endpoint.name or "") serviceIndex
      && (serviceIndex.${endpoint.name}.providerRole or null) == "core"
      && builtins.elem (serviceIndex.${endpoint.name}.providerNode or null) (nodesByRole "core")
    then
      [ serviceIndex.${endpoint.name}.providerNode ]
    else
      coresForExternal endpoint;

  hostTenant =
    providerName:
    let
      matches = lib.filter (
        host:
        builtins.isAttrs host
        && toString (host.name or "") == toString providerName
        && (host.tenant or null) != null
      ) hosts;
    in
    if matches == [ ] then null else toString ((builtins.head matches).tenant);

  serviceTenants =
    serviceName:
    let
      service = serviceIndex.${serviceName} or null;
      providers =
        if service != null && builtins.isList (service.providers or null) then service.providers else [ ];
    in
    lib.unique (lib.filter (tenant: tenant != null) (map hostTenant providers));

  endpointTenants =
    endpoint:
    if !(builtins.isAttrs endpoint) then
      [ ]
    else if (endpoint.kind or null) == "tenant" then
      [ endpoint.name ]
    else if (endpoint.kind or null) == "tenant-set" then
      endpoint.members or [ ]
    else if (endpoint.kind or null) == "service" && (endpoint.name or null) != null then
      serviceTenants endpoint.name
    else
      [ ];

  accessForEndpoint =
    endpoint:
    let
      tenantNames = endpointTenants endpoint;
      matches =
        if tenantNames == [ ] then
          [ ]
        else
          lib.filter (
            name:
            builtins.any (
              attachment:
              (attachment.kind or null) == "tenant" && builtins.elem (attachment.name or null) tenantNames
            ) (nodes.${name}.attachments or [ ])
          ) (nodesByRole "access");
    in
    if matches == [ ] then firstRole "access" else builtins.head matches;

in
{
  inherit
    accessNodes
    firstRole
    coresForExternal
    coresForEndpoint
    accessForEndpoint
    ;
}
