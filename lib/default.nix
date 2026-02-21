{ lib }:
let
  compileContract = import ./contract/compile.nix { inherit lib; };

  generateP2P = import ./pipeline/generate-p2p.nix { inherit lib; };

  verify = import ./pipeline/verify.nix { inherit lib; };

  stages = import ./stages.nix { inherit lib; };
in
{
  inherit
    compileContract
    generateP2P
    verify
    stages
    ;
}
