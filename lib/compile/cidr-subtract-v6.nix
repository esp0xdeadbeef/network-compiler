# FILE: ./lib/compile/cidr-subtract-v6.nix
{ lib }:

let
  net = lib.net;

  isV6 = s: builtins.isString s && lib.hasInfix ":" s && lib.hasInfix "/" s;

  normalize = c: net.cidr.canonicalize c;

  contains = super: sub: net.cidr.contains (net.cidr.ip sub) super;

  subtractOne =
    acc: block:
    lib.concatMap (
      p:
      if contains block p then
        [ ]
      else if contains p block then
        let
          len = net.cidr.length p;
          next = len + 1;
          baseIp = net.cidr.ip p;
          left = net.cidr.make next baseIp;
          right = net.cidr.hostCidr (net.cidr.capacity left) left;
        in
        lib.filter (x: x != null) [
          left
          right
        ]
      else
        [ p ]
    ) acc;

in

blockedCidrs:

let
  universe = [ "::/0" ];
  blocked = map normalize (lib.filter isV6 blockedCidrs);
in
lib.foldl' subtractOne universe blocked
