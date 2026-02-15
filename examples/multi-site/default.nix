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

      nebulaAddr4 = "172.16.${toString nebulaBaseOctet}.3/31";
      nebulaGw4 = "172.16.${toString nebulaBaseOctet}.3";

      nebulaAddr6 = "${cfg.ulaPrefix}:ffff::3/127";
      nebulaGw6 = "${cfg.ulaPrefix}:ffff::3";

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

              routes4 = [
                {
                  dst = "0.0.0.0/0";
                  via4 = nebulaGw4;
                }
              ];

              routes6 = [
                {
                  dst = "::/0";
                  via6 = nebulaGw6;
                }
              ];
            };
          };
        };
      };
    in
    cfg
    // {
      links = nebulaLink // (cfg.links or { });
    };
in
builtins.mapAttrs mkSite sites
