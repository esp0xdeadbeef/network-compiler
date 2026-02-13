{ lib, model }:

let

  validated = import ./validate.nix { inherit lib model; };

  defaultAssertions = import ./assertions/default.nix { inherit lib; } validated;

  _defaultAssert = lib.assertMsg (lib.all (a: a.assertion) (defaultAssertions.assertions or [ ])) (
    lib.concatStringsSep "\n" (
      map (a: a.message) (lib.filter (a: !a.assertion) (defaultAssertions.assertions or [ ]))
    )
  );

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

  routed = import ./routing-gen.nix {
    inherit lib ulaPrefix tenantV4Base;
  } validated;

in

builtins.seq _defaultAssert routed
