{
  badsite = {
    ownership = {
      prefixes = [
        {
          kind = "tenant";
          name = "mgmt";
          ipv4 = "10.20.10.0/24";
          ipv6 = "fd42:dead:beef:10::/64";
        }
      ];
    };

    pools = {
      p2p = {
        ipv4 = "10.10.0.0/24";
        ipv6 = "fd42:dead:beef:1000::/118";
      };

      loopback = {
        ipv4 = "10.19.0.0/24";
        ipv6 = "fd42:dead:beef:1900::/118";
      };
    };

    topology = {
      nodes = {
        s-router-core = {
          role = "core";
          uplinks = {
            uplink0 = {
              ipv4 = [ "0.0.0.0/0" ];
              ipv6 = [ "::/0" ];
            };
          };
        };

        s-router-upstream-selector = {
          role = "upstream-selector";
        };

        s-router-policy = {
          role = "policy";
        };

        s-router-downstream-selector = {
          role = "downstream-selector";
        };

        s-router-access = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "mgmt";
            }
          ];
        };
      };

      links = [
        [
          "s-router-core"
          "s-router-upstream-selector"
        ]
        [
          "s-router-upstream-selector"
          "s-router-policy"
        ]
        [
          "s-router-policy"
          "s-router-downstream-selector"
        ]
        [
          "s-router-downstream-selector"
          "s-router-access"
        ]
      ];
    };

    communicationContract = {
      trafficTypes = [ ];

      services = [ ];

      relations = [
        {
          id = "duplicate-id";
          priority = 100;
          from = {
            kind = "tenant";
            name = "mgmt";
          };
          to = {
            kind = "external";
            uplinks = [ "uplink0" ];
          };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "duplicate-id";
          priority = 200;
          from = {
            kind = "tenant";
            name = "mgmt";
          };
          to = {
            kind = "external";
            uplinks = [ "uplink0" ];
          };
          trafficType = "any";
          action = "deny";
        }
      ];
    };
  };
}
