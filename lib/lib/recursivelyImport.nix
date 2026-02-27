{ nix }:
let
  err =
    if nix ? lib && nix.lib ? throwError then
      nix.lib
    else if
      nix ? inputs
      && nix.inputs ? nixpkgs
      && nix.inputs.nixpkgs ? lib
      && nix.inputs.nixpkgs.lib ? throwError
    then
      nix.inputs.nixpkgs.lib
    else
      null;
in
if nix ? lib then
  nix.lib
else if nix ? inputs && nix.inputs ? nixpkgs && nix.inputs.nixpkgs ? lib then
  nix.inputs.nixpkgs.lib
else
  (import ../error.nix { lib = (import <nixpkgs> { }).lib; }).throwError {
    code = "E_RECURSIVE_IMPORT_LIB_RESOLUTION";
    site = null;
    path = [
      "lib"
      "lib"
      "recursivelyImport.nix"
    ];
    message = "could not resolve nixpkgs lib";
    hints = [
      "Pass an attrset that includes .lib"
      "Or pass a flake-like attrset with .inputs.nixpkgs.lib"
    ];
  }
