{
  sopsData ? { },
}:

let
  sites = {
    site-a = import ./sites/site-a.nix;
    site-b = import ./sites/site-b.nix;
  };

  mkSite =
    name: siteCfg:
    let
      cfg = siteCfg;

      siteHash = builtins.fromTOML "x = 0x${builtins.substring 0 2 (builtins.hashString "sha256" name)}";

      nebulaBaseOctet = siteHash.x;

      nebulaAddr4 = "172.16.${toString nebulaBaseOctet}.2/31";
      nebulaGw4 = "172.16.${toString nebulaBaseOctet}.1";

      nebulaAddr6 = "${cfg.ulaPrefix}:ffff::2/127";
      nebulaGw6 = "${cfg.ulaPrefix}:ffff::1";

      tenantLinks = builtins.listToAttrs (
        map (
          vlan:
          let
            vStr = toString vlan;
          in
          {
            name = "tenant-${vStr}";
            value = {
              kind = "lan";
              carrier = "fabric";
              vlanId = vlan;
              name = "tenant-${vStr}";
              members = [
                cfg.coreNodeName
                cfg.policyNodeName
              ];
              endpoints = {
                "${cfg.coreNodeName}-tenant-${vStr}" = {
                  addr4 = "${cfg.tenantV4Base}.${vStr}.1/24";
                  addr6 = "${cfg.ulaPrefix}:${vStr}::1/64";
                };
                "${cfg.policyNodeName}-tenant-${vStr}" = {
                  addr4 = "${cfg.tenantV4Base}.${vStr}.254/24";
                  addr6 = "${cfg.ulaPrefix}:${vStr}::fe/64";
                };
              };
            };
          }
        ) cfg.tenantVlans
      );

      nebulaRoutes4 = map (
        vlan:
        let
          vStr = toString vlan;
        in
        {
          dst = "${cfg.tenantV4Base}.${vStr}.0/24";
          via4 = nebulaGw4;
        }
      ) cfg.tenantVlans;

      nebulaRoutes6 = map (
        vlan:
        let
          vStr = toString vlan;
        in
        {
          dst = "${cfg.ulaPrefix}:${vStr}::/64";
          via6 = nebulaGw6;
        }
      ) cfg.tenantVlans;

      nebulaLink = {
        nebula = {
          kind = "wan";
          carrier = "wan";
          vlanId = 8;
          name = "nebula";
          members = [ cfg.coreNodeName ];
          endpoints = {
            "${cfg.coreNodeName}-nebula" = {
              addr4 = nebulaAddr4;
              addr6 = nebulaAddr6;
              routes4 = nebulaRoutes4;
              routes6 = nebulaRoutes6;
            };
          };
        };
      };
    in
    cfg
    // {
      links = nebulaLink // (cfg.links or { }) // tenantLinks;
    };
in
builtins.mapAttrs mkSite sites
