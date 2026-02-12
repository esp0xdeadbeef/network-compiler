{ lib }:

{ topology }:

let
  # evaluate user-supplied topology (pure, no env, no <nixpkgs>, no absolute paths)
  raw = if builtins.isFunction topology then topology { inherit lib; } else topology;

  resolved = import ./topology-resolve.nix {
    inherit lib;
    ulaPrefix = raw.ulaPrefix or "fd42:dead:beef";
    tenantV4Base = raw.tenantV4Base or "10.10";
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
