{ lib }:

siteKey: nodes: coreUplinks: serviceIndex: hosts:
{
  overlays ? [ ],
}:

let
  roles = import ./selectors/roles.nix { inherit lib; } siteKey nodes coreUplinks {
    inherit overlays;
  };
  inherit (roles)
    nodeNames
    nodesByRole
    firstRole
    accessNodes
    uplinkNamesForCore
    selectsOf
    coresForSelection
    coresForExternal
    ;

  exitsForRelation =
    relation:
    let
      endpoint = relation.to or { };
      # FS-210/FS-525: a service destination's exit is the node that hosts the
      # service (`providerNode`), resolved by coresForEndpoint. A service name
      # is not an exit scope, so it must not be pinned here.
      isServiceDestination = builtins.isAttrs endpoint && (endpoint.kind or null) == "service";
      pinned =
        if isServiceDestination then
          [ ]
        else if builtins.isAttrs endpoint && endpoint ? scope then
          [ endpoint.scope ]
        else if builtins.isAttrs endpoint && endpoint ? name then
          [ endpoint.name ]
        else
          [ ];
      fromScope =
        let
          tenants = endpointTenants relation.from;
          matches =
            if tenants == [ ] then
              [ ]
            else
              lib.filter (
                name:
                builtins.any (
                  attachment: (attachment.kind or null) == "tenant" && builtins.elem (attachment.name or null) tenants
                ) (nodes.${name}.attachments or [ ])
              ) nodeNames;
        in
        if matches == [ ] then null else builtins.head matches;
      selections =
        if isServiceDestination then
          [ ]
        else if pinned != [ ] then
          pinned
        else if fromScope != null then
          selectsOf fromScope
        else
          [ ];
    in
    lib.unique (lib.concatMap coresForSelection selections);

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
    exitsForRelation
    ;
}
