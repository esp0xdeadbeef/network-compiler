{ lib }:

let
  net = lib.net;

  isV4 = s: builtins.isString s && lib.hasInfix "." s && lib.hasInfix "/" s;

  normalize = c: net.cidr.canonicalize c;

  contains = super: sub: net.cidr.contains (net.cidr.ip sub) super;

  subtractOne =
    acc: block:
    lib.concatMap (
      p:
      if contains block p then
        # fully covered → drop
        [ ]
      else if contains p block then
        # block inside p → split once into two halves
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
  universe = [ "0.0.0.0/0" ];
  blocked = map normalize (lib.filter isV4 blockedCidrs);
in
lib.foldl' subtractOne universe blocked
