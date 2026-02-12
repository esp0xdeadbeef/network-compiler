{
  sopsData ? { },
}:

let
  base = {
    tenantVlans = [
      10
      20
      30
      40
      50
      60
      70
      80
    ];

    ulaPrefix = "fd42:dead:beef";
    tenantV4Base = "10.10";

    policyAccessTransitBase = 100;
    policyAccessOffset = 0;

    corePolicyTransitVlan = 200;

    links = {
      isp-1 = {
        kind = "wan";
        carrier = "wan";
        vlanId = 6;
        name = "isp-1";
        members = [ "s-router-core-wan" ];
        endpoints = {
          "s-router-core-wan" = {
            addr6 = "2001:db8:1::2/48";
            routes6 = [ { dst = "::/0"; } ];
          };
        };
      };

      isp-2 = {
        kind = "wan";
        carrier = "wan";
        vlanId = 7;
        name = "isp-2";
        members = [ "s-router-core-wan" ];
        endpoints = {
          "s-router-core-wan" = {
            addr6 = "2001:db8:2::2/48";
            routes6 = [ { dst = "::/0"; } ];
          };
        };
      };

      nebula = {
        kind = "wan";
        carrier = "wan";
        vlanId = 8;
        name = "nebula";
        members = [ "s-router-core-wan" ];
        endpoints = {
          "s-router-core-wan" = {
            addr4 = "100.64.10.2/32";
            routes4 = [ { dst = "10.9.0.0/16"; } ];
          };
        };
      };
    };
  };
in
base // sopsData
