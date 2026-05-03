{ lib }:

let
  err = import ../error.nix { inherit lib; };
  ipv4 = import ./ipv4.nix { inherit lib err; };
  ipv6 = import ./ipv6.nix { inherit lib err; };
in
{
  inherit (ipv4) mkIPv4Allocator;
  inherit (ipv6) mkIPv6Allocator;
}
