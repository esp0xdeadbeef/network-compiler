{ lib }:

{
  siteKey,
  tenantNames,
  accessNames,
  clientNames,
  ensure,
  basePath,
}:

idx: field: endpoint:
let
  kind = endpoint.kind or null;
  name = endpoint.name or null;
  validName =
    if kind == "tenant" then
      builtins.elem name tenantNames
    else if kind == "access" then
      builtins.elem name accessNames
    else if kind == "client" then
      builtins.elem name clientNames
    else
      false;
  check =
    cond: code: extra: message: hints:
    ensure cond {
      inherit code siteKey;
      site = siteKey;
      path = basePath idx ([ field ] ++ extra);
      inherit message hints;
    };
  _shape = check (builtins.isAttrs endpoint) "E_ISOLATION_ENDPOINT_SHAPE" [ ]
    "isolation decision '${field}' endpoint must be an attrset"
    [ "Use { kind = \"tenant\"|\"access\"|\"client\"; name = \"...\"; }." ];
  _kind = check (builtins.elem kind [ "tenant" "access" "client" ]) "E_ISOLATION_ENDPOINT_KIND" [ "kind" ]
    "isolation decision endpoint kind must be tenant, access, or client"
    [ "Use tenant, access, or client identity consumed by the compiler." ];
  _name = check (name != null && builtins.isString name && name != "") "E_ISOLATION_ENDPOINT_NAME" [ "name" ]
    "isolation decision endpoint requires a non-empty name"
    [ "Name an existing tenant, access node, or client endpoint." ];
  _exists = check validName "E_ISOLATION_ENDPOINT_UNKNOWN" [ "name" ]
    "isolation decision endpoint '${kind}:${name}' is not a consumed compiler interface"
    [
      "Tenant names come from ownership.prefixes."
      "Access names come from topology.nodes with role = \"access\"."
      "Client names come from ownership.endpoints host records."
    ];
in
builtins.seq _shape (
  builtins.seq _kind (
    builtins.seq _name (
      builtins.seq _exists {
        inherit kind name;
      }
    )
  )
)
