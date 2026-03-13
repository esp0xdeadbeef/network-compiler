{
  esp0xdeadbeef.site-a = {

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

    ownership = {
      prefixes = [
        {
          kind = "tenant";
          name = "mgmt";
          ipv4 = "10.20.10.0/24";
          ipv6 = "fd42:dead:beef:10::/64";
        }
        {
          kind = "tenant";
          name = "admin";
          ipv4 = "10.20.15.0/24";
          ipv6 = "fd42:dead:beef:15::/64";
        }
        {
          kind = "tenant";
          name = "client";
          ipv4 = "10.20.20.0/24";
          ipv6 = "fd42:dead:beef:20::/64";
        }
      ];
    };

    communicationContract = {

      trafficTypes = [
        {
          name = "any";
          match = [
            {
              family = "any";
            }
          ];
        }
      ];

      services = [ ];

      relations = [
        {
          id = "allow-admin-to-any";
          priority = 100;
          from = {
            kind = "tenant";
            name = "admin";
          };
          to = {
            kind = "any";
          };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "allow-mgmt-to-any";
          priority = 100;
          from = {
            kind = "tenant";
            name = "mgmt";
          };
          to = {
            kind = "any";
          };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "allow-client-to-any";
          priority = 100;
          from = {
            kind = "tenant";
            name = "client";
          };
          to = {
            kind = "any";
          };
          trafficType = "any";
          action = "allow";
        }
      ];
    };

    topology = {
      nodes = {
        s-router-core-wan = {
          role = "core";
          uplinks = {
            wan = {
              ipv4 = [ "0.0.0.0/0" ];
              ipv6 = [ "::/0" ];
            };
          };
        };

        s-router-core-nebula = {
          role = "core";
          uplinks = {
            nebula = {
              ipv4 = [ "100.64.0.0/64" ];
              ipv6 = [ "fd42::/48" ];

              ingressSubject = {
                kind = "tenant";
                name = "admin";
              };
            };
          };
        };

        s-router-upstream-selector = {
          role = "upstream-selector";
        };

        s-router-policy = {
          role = "policy";
        };

        s-router-access-mgmt = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "mgmt";
            }
          ];
        };

        s-router-access-admin = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "admin";
            }
          ];
        };

        s-router-access-client = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "client";
            }
          ];
        };
      };

      links = [
        [
          "s-router-core-wan"
          "s-router-upstream-selector"
        ]
        [
          "s-router-core-nebula"
          "s-router-upstream-selector"
        ]
        [
          "s-router-upstream-selector"
          "s-router-policy"
        ]
        [
          "s-router-policy"
          "s-router-access-client"
        ]
        [
          "s-router-policy"
          "s-router-access-admin"
        ]
        [
          "s-router-policy"
          "s-router-access-mgmt"
        ]
      ];
    };
  };
}
