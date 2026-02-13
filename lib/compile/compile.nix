{ lib, model }:

let
  # ------------------------------------------------------------
  # Site validation (VLAN policy etc.)
  # ------------------------------------------------------------
  validated = import ./validate.nix { inherit lib model; };

  # ------------------------------------------------------------
  # Default-route & WAN consistency assertions (PRE-ROUTING)
  # ------------------------------------------------------------
  defaultAssertions = import ./assertions/default.nix { inherit lib; } validated;

  _defaultAssert = lib.assertMsg (lib.all (a: a.assertion) (defaultAssertions.assertions or [ ])) (
    lib.concatStringsSep "\n" (
      map (a: a.message) (lib.filter (a: !a.assertion) (defaultAssertions.assertions or [ ]))
    )
  );

  # ------------------------------------------------------------
  # Required addressing inputs
  # ------------------------------------------------------------
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

  # ------------------------------------------------------------
  # Routing pipeline (includes pre/post routing assertions)
  # ------------------------------------------------------------
  routed = import ./routing-gen.nix {
    inherit lib ulaPrefix tenantV4Base;
  } validated;

in
# Force evaluation of default assertions before routing
builtins.seq _defaultAssert routed
