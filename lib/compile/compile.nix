{ lib, model }:

let
  ulaPrefix = model.ulaPrefix or "fd00::";

  tenantV4Base = model.tenantV4Base or "10.0";
in
import ./routing-gen.nix {
  inherit lib ulaPrefix tenantV4Base;
} model
