let
  base = rec {
    siteName = "site-b";
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
    ulaPrefix = "fd42:dead:beef:b";
    tenantV4Base = "10.30";

    policyAccessTransitBase = 100;
    policyAccessOffset = 0;

    corePolicyTransitVlan = 200;

    policyNodeName = "site-b-s-router-policy-only";
    coreNodeName = "site-b-s-router-core";

    defaultRouteMode = "default";

    policyIntent = {
      exitTenants = tenantVlans;
      upstreamClasses = [
        "default"
        "internet"
      ];
      advertiseClasses = [
        "default"
        "internet"
      ];
    };

    links = {
      isp-1 = {
        kind = "wan";
        carrier = "wan";
        vlanId = 4;
        name = "isp-1";
        members = [ coreNodeName ];
        endpoints = {
          "${coreNodeName}-isp-1" = {
            dhcp = true;
            acceptRA = true;
            routes4 = [ { dst = "0.0.0.0/0"; } ];
            routes6 = [ { dst = "::/0"; } ];
          };
        };
      };

      isp-2 = {
        kind = "wan";
        carrier = "wan";
        vlanId = 7;
        name = "isp-2";
        members = [ coreNodeName ];
        endpoints = {
          "${coreNodeName}-isp-2" = {
            dhcp = true;
            acceptRA = true;
            routes4 = [ { dst = "0.0.0.0/0"; } ];
            routes6 = [ { dst = "::/0"; } ];
          };
        };
      };
    };
  };
in
base
