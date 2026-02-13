{
  sopsData ? { },
}:

let
  base = rec {
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

    defaultRouteMode = "default";

    links = {
      isp-1 = {
        kind = "wan";
        carrier = "wan";
        vlanId = 4;
        name = "isp-1";
        members = [ "s-router-core-wan" ];
        endpoints = {
          "s-router-core-wan" = {
            addr4 = "10.11.0.40/24";
            addr6 = "fd11:dead:beef:0::1337/64";

            routes6 = [
              { dst = "::/0"; }
              {
                dst = "0.0.0.0/0";
                nat = true;
                gateway = "10.11.0.1/24";
              }
            ];

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
            addr4 = "10.13.0.40/24";
            addr6 = "fd13:dead:beef:0::1337/64";

            routes6 = [
              {
                dst = "::/0";
                nat = true;
                gateway = "10.13.0.1/24";
              }
            ];
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

            routes4 =
              if defaultRouteMode == "default" then
                [
                  { dst = "0.0.0.0/0"; }
                ]
              else
                [ ];
          };
        };
      };
    };
  };
in
base // sopsData
