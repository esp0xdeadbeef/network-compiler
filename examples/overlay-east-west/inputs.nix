{
  enterprise-a.site-a = {
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

    policy = {
      external.wantDefault = true;
      external.wantFullTables = false;
      catalog.services = [ ];
      nat.ingress = [ ];

      rules = [
        {
          id = "allow-mgmt-to-overlay-east-west";
          priority = 100;
          from = {
            kind = "tenant";
            name = "mgmt";
          };
          to = {
            external = "east-west";
          };
          proto = [ "any" ];
          action = "allow";
        }
      ];
    };

    transport.overlays = [
      {
        name = "east-west";
        peerSite = "enterprise-b.site-b";
        terminateOn = "s-router-core";
        mustTraverse = [ "policy" ];
      }
    ];

    topology = {
      nodes = {
        s-router-core = {
          role = "core";
          upstreams = {
            isp = { };
            overlay-east-west = { };
          };
        };

        s-router-upstream-selector = {
          role = "upstream-selector";
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
          "s-router-upstream-selector"
        ]
        [
          "s-router-upstream-selector"
          "s-router-policy"
        ]
        [
          "s-router-policy"
          "s-router-access"
        ]
      ];
    };
  };

  enterprise-b.site-b = {
    pools = {
      p2p = {
        ipv4 = "10.11.0.0/24";
        ipv6 = "fd42:dead:beef:1100::/118";
      };
      loopback = {
        ipv4 = "10.29.0.0/24";
        ipv6 = "fd42:dead:beef:2900::/118";
      };
    };

    ownership.prefixes = [
      {
        kind = "tenant";
        name = "mgmt";
        ipv4 = "10.30.10.0/24";
        ipv6 = "fd42:dead:beef:11::/64";
      }
    ];

    policy = {
      external.wantDefault = true;
      external.wantFullTables = false;
      catalog.services = [ ];
      nat.ingress = [ ];

      rules = [
        {
          id = "allow-mgmt-to-overlay-east-west";
          priority = 100;
          from = {
            kind = "tenant";
            name = "mgmt";
          };
          to = {
            external = "east-west";
          };
          proto = [ "any" ];
          action = "allow";
        }
      ];
    };

    transport.overlays = [
      {
        name = "east-west";
        peerSite = "enterprise-a.site-a";
        terminateOn = "s-router-core";
        mustTraverse = [ "policy" ];
      }
    ];

    topology = {
      nodes = {
        s-router-core = {
          role = "core";
          upstreams = {
            isp = { };
            overlay-east-west = { };
          };
        };

        s-router-upstream-selector = {
          role = "upstream-selector";
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
          "s-router-upstream-selector"
        ]
        [
          "s-router-upstream-selector"
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
