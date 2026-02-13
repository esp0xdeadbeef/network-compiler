# ./lib/eval.nix
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

in
compiled
