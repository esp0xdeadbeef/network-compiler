{ lib }:
{
  compile = import ./main.nix { inherit lib; };
}
