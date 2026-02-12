{ lib }:

{ topology }:

let
  raw = if builtins.isFunction topology then topology { inherit lib; } else topology;

  ulaPrefix =
    if raw ? ulaPrefix then raw.ulaPrefix else throw "evalNetwork: topology must define 'ulaPrefix'";

  tenantV4Base =
    if raw ? tenantV4Base then
      raw.tenantV4Base
    else
      throw "evalNetwork: topology must define 'tenantV4Base'";

  resolved = import ./topology-resolve.nix {
    inherit lib ulaPrefix tenantV4Base;
  } raw;

  compiled = import ./compile/compile.nix {
    inherit lib;
    model = resolved;
  };

  sanitize =
    x:
    let
      t = builtins.typeOf x;
    in
    if t == "lambda" || t == "primop" then
      "<function>"
    else if builtins.isList x then
      map sanitize x
    else if builtins.isAttrs x then
      lib.mapAttrs (_: v: sanitize v) x
    else if t == "path" then
      toString x
    else
      x;

in
sanitize {
  topology = {
    domain = compiled.domain or null;
    nodes = builtins.attrNames (compiled.nodes or { });
    links = builtins.attrNames (compiled.links or { });
  };

  nodes = compiled.nodes or { };
  links = compiled.links or { };
}
