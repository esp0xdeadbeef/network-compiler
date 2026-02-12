# FILE: ./dev/debug-lib/30-routing.nix
{
  sopsData ? { },
}:
let
  pkgs = null;
  flake = builtins.getFlake (toString ../../.);
  lib = flake.lib;
  cfg = import ./inputs.nix { inherit sopsData; };

  resolved = import ./20-topology-resolved.nix { inherit sopsData; };

  haveWan = builtins.isAttrs sopsData && (sopsData ? wan) && builtins.isAttrs sopsData.wan;

  mkWanLink = name: wan: {
    kind = "wan";
    carrier = "wan";
    vlanId = wan.vlanId or 6;
    name = "wan-${name}";
    members = [ "s-router-core-wan" ];
    endpoints = {
      "s-router-core-wan" = {
        routes4 = lib.optional (wan ? ip4) { dst = "0.0.0.0/0"; };
        routes6 = lib.optional (wan ? ip6) { dst = "::/0"; };
      }
      // lib.optionalAttrs (wan ? ip4) { addr4 = wan.ip4; }
      // lib.optionalAttrs (wan ? ip6) { addr6 = wan.ip6; };
    };
  };

  wanLinks = if haveWan then lib.mapAttrs (name: wan: mkWanLink name wan) sopsData.wan else { };

  withWan = resolved // {
    links = (resolved.links or { }) // wanLinks;
  };

in
import ../../lib/compile/routing-gen.nix {
  inherit lib;
  inherit (cfg) ulaPrefix tenantV4Base;
} withWan
