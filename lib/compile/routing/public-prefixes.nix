{ lib }:

let
  cidrSubtract4 = import ../cidr-substract.nix { inherit lib; };
  cidrSubtract6 = import ../cidr-subtract-v6.nix { inherit lib; };

  is4 = p: lib.hasInfix "." p;
  is6 = p: lib.hasInfix ":" p;
  isCidr = s: builtins.isString s && (lib.hasInfix "/" s);

in

topo:

let
  defaultRouteMode = if topo ? defaultRouteMode then topo.defaultRouteMode else "default";

  doComputed = defaultRouteMode == "computed";

  collectFromEndpoint =
    ep:
    (lib.optional (ep ? addr4) ep.addr4)
    ++ (lib.optional (ep ? addr6) ep.addr6)
    ++ (lib.optional (ep ? addr6Public) ep.addr6Public);

  collectOwned = lib.flatten (
    lib.mapAttrsToList (
      _: l: lib.flatten (lib.mapAttrsToList (_: ep: collectFromEndpoint ep) (l.endpoints or { }))
    ) (topo.links or { })
  );

  ownedRaw = collectOwned;
  owned = lib.unique (lib.filter isCidr ownedRaw);

  owned4 = lib.filter is4 owned;
  owned6 = lib.filter is6 owned;

  reserved4 = [
    "0.0.0.0/8"
    "10.0.0.0/8"
    "100.64.0.0/10"
    "127.0.0.0/8"
    "169.254.0.0/16"
    "172.16.0.0/12"
    "192.168.0.0/16"
    "224.0.0.0/4"
    "240.0.0.0/4"
  ];

  reserved6 = [
    "fc00::/7"
    "fe80::/10"
    "::1/128"
    "::/128"
  ];

  internet4 =
    if doComputed then
      cidrSubtract4 {
        universe = "0.0.0.0/0";
        blockedCidrs = reserved4 ++ owned4;
      }
    else
      [ "0.0.0.0/0" ];

  internet6 =
    if doComputed then
      cidrSubtract6 {
        universe = "::/0";
        blockedCidrs = reserved6 ++ owned6;
      }
    else
      [ "::/0" ];

in
{
  inherit internet4 internet6;
}
