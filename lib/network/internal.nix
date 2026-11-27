# VENDORED, DO NOT RE-PIN.
#
# This is `lib/network` from the patched nixpkgs this repository used to consume as
# `nixpkgs-network` (an absolute rev, github:NixOS/nixpkgs/ac56c456..., dated
# 2024-07-27). That patch is not going to land in nixpkgs, so carrying a second
# nixpkgs to obtain 600 lines of IPv6 helpers meant every lock in the fleet held a
# nixpkgs graph nobody could move: several nixpkgs revisions per lock, each with its
# own stdenv, only one of which any warm could cover.
#
# It lives here now as an ordinary library. `lib` is a parameter rather than
# `import ../.`, because `../.` was nixpkgs' own lib and means something else here.
#
# SPLIT INTO PARTS, and not for tidiness: these definitions are mutually recursive
# (`expandIpv6` calls `parseExpandedIpv6` and back, `pow` calls `calculateFirstAddress`
# and back), so the parts are knotted through `self` here. A single file was 423 lines,
# and tests/test-nix-file-loc.sh fails any tracked .nix over 200 lines with no note able
# to waive it -- measured as the one failing job in run 45932175985.
{ lib }:
let
  self = {
    constants = import ./internal/constants.nix { inherit lib; inherit self; };
    parsers = import ./internal/parsers.nix { inherit lib; inherit self; };
    addresses = import ./internal/addresses.nix { inherit lib; inherit self; };
    types = import ./internal/types.nix { inherit lib; inherit self; };
  };
in
{
  _common = {
    inherit (self.parsers) modList;
  };

  _ipv6 = self.types._ipv6;
}
