{ sopsData ? {} }:
let
  pkgs = null;
  lib = import <nixpkgs/lib>;
  cfg = import ./inputs.nix { inherit sopsData; };

  withNebula = import ./25-topology-with-nebula.nix { inherit sopsData; };

  # Optional: if caller didn't supply sopsData.wan, just don't add WAN links.
  haveWan =
    builtins.isAttrs sopsData && (sopsData ? wan) && builtins.isAttrs sopsData.wan;

  stripCidr = s: builtins.elemAt (lib.splitString "/" s) 0;

  mkWanLink =
    name: wan:
    let
      ip4 = if builtins.hasAttr "ip4" wan then "${stripCidr wan.ip4}/32" else null;
      ip6 = if builtins.hasAttr "ip6" wan then "${stripCidr wan.ip6}/128" else null;
    in
    {
      kind = "wan";
      carrier = "wan";
      vlanId = 6;
      name = "wan-${name}";
      members = [ "s-router-core-wan" ];
      endpoints = {
        "s-router-core-wan" =
          {
            routes4 = lib.optional (ip4 != null) { dst = "0.0.0.0/0"; };
            routes6 = lib.optional (ip6 != null) { dst = "::/0"; };
          }
          // lib.optionalAttrs (ip4 != null) { addr4 = ip4; }
          // lib.optionalAttrs (ip6 != null) { addr6 = ip6; };
      };
    };

  wanLinks =
    if haveWan then
      lib.mapAttrs (name: wan: mkWanLink name wan) sopsData.wan
    else
      { };

  withWan = withNebula // {
    links = withNebula.links // wanLinks;
  };

in
import ../../lib/compile/routing-gen.nix {
  inherit lib;
  inherit (cfg) ulaPrefix tenantV4Base;
} withWan

