{
  sopsData ? { },
}:
let
  common = import ./common.nix { inherit sopsData; };
  inherit (common) lib cfg;

  topoRaw = import ./10-topology-raw.nix { inherit sopsData; };

  coreNodeName = cfg.coreNodeName or "s-router-core";

  haveWan = builtins.isAttrs sopsData && (sopsData ? wan) && builtins.isAttrs sopsData.wan;

  mkWanLink =
    ctx: wan:
    let
      coreCtx = "${coreNodeName}-${ctx}";

      dhcp = wan.dhcp or false;
      acceptRA = wan.acceptRA or false;

      wantDefault4 = dhcp || (wan ? routes4) || (wan ? ip4);
      wantDefault6 = dhcp || acceptRA || (wan ? routes6) || (wan ? ip6);

      routes4 =
        if wan ? routes4 then
          wan.routes4
        else if wantDefault4 then
          [ { dst = "0.0.0.0/0"; } ]
        else
          [ ];

      routes6 =
        if wan ? routes6 then
          wan.routes6
        else if wantDefault6 then
          [ { dst = "::/0"; } ]
        else
          [ ];
    in
    {
      kind = "wan";
      carrier = "wan";
      vlanId = wan.vlanId or 6;
      name = "wan-${ctx}";
      members = [ coreNodeName ];

      endpoints."${coreCtx}" = {
        inherit routes4 routes6;
      }
      // lib.optionalAttrs (wan ? ip4) { addr4 = wan.ip4; }
      // lib.optionalAttrs (wan ? ip6) { addr6 = wan.ip6; }
      // lib.optionalAttrs (wan ? acceptRA) { acceptRA = wan.acceptRA; }
      // lib.optionalAttrs (wan ? dhcp) { dhcp = wan.dhcp; };
    };

  wanLinks = if haveWan then lib.mapAttrs mkWanLink sopsData.wan else { };

  topoWithLinks = topoRaw // {
    defaultRouteMode = cfg.defaultRouteMode or "default";
    coreRoutingNodeName = cfg.coreRoutingNodeName or null;

    links = (topoRaw.links or { }) // (cfg.links or { }) // wanLinks;
  };

  resolved = import ../../lib/topology-resolve.nix {
    inherit lib;
    inherit (cfg) ulaPrefix tenantV4Base;
  } topoWithLinks;

in
import ../../lib/compile/routing-gen.nix {
  inherit lib coreNodeName;
  inherit (cfg)
    ulaPrefix
    tenantV4Base
    ;
  coreRoutingNodeName = cfg.coreRoutingNodeName or null;
  policyNodeName = cfg.policyNodeName or "s-router-policy-only";
} resolved
