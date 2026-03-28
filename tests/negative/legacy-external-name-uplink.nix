{
  badsite = {
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
          id = "allow-mgmt-to-uplink0";
          priority = 100;
          from = {
            kind = "tenant";
            name = "mgmt";
          };
          to = {
            kind = "external";
            name = "uplink0";
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
            uplink0 = {
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
