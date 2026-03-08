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
          id = "allow-mgmt-to-east-west";
          priority = 100;
          from = {
            kind = "tenant";
            name = "mgmt";
          };
          to = {
            kind = "external";
            name = "east-west";
          };
          trafficType = "any";
          action = "allow";
        }
      ];
    };

    transport.overlays = [
      {
        name = "east-west";
        peerSite = "default.other";
        terminateOn = "s-router-core";
        mustTraverse = [ "policy" ];
      }
    ];

    topology = {
      nodes = {
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
          "s-router-policy"
          "s-router-access"
        ]
      ];
    };
  };
}
