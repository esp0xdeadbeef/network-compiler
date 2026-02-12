{ lib, model }:

let
  validated = import ./validate.nix { inherit lib model; };

  ulaPrefix =
    if validated ? ulaPrefix then
      validated.ulaPrefix
    else
      throw "compile: missing required attribute 'ulaPrefix' in model";

  tenantV4Base =
    if validated ? tenantV4Base then
      validated.tenantV4Base
    else
      throw "compile: missing required attribute 'tenantV4Base' in model";

in
import ./routing-gen.nix {
  inherit lib ulaPrefix tenantV4Base;
} validated
