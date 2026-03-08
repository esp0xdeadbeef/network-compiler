{
  badsite = {
    pools = {
      p2p = {
        ipv4 = "10.10.0.0/30";
        ipv6 = "fd42:dead:beef:1000::/126";
      };
      loopback = {
        ipv4 = "10.19.0.0/30";
        ipv6 = "fd42:dead:beef:1900::/126";
      };
    };

    ownership.prefixes = [
      {
        kind = "tenant";
        name = "mgmt";
        ipv4 = "10.20.10.0/24";
        ipv6 = "fd42:dead:beef:10::/64";
      }
    ];

    communicationContract = {
      trafficTypes = [ ];
      services = [ ];
      relations = [
        {
          id = "allow-mgmt-to-wan";
          priority = 100;
          from = {
            kind = "tenant";
            name = "mgmt";
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "any";
          action = "allow";
        }
      ];
    };

    topology = {
      nodes = {
        s-router-core = {
          role = "core";
          uplinks = {
            wan = {
              ipv4 = [ "0.0.0.0/0" ];
              ipv6 = [ "::/0" ];
            };
          };
        };

        s-router-policy = {
          role = "policy";
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
          "s-router-policy"
        ]
        [
          "s-router-policy"
          "s-router-access"
        ]
      ];
    };
  };
}
