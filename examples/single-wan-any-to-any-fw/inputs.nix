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

      endpoints = [
        {
          kind = "host";
          name = "s-sigma";
          tenant = "mgmt";
        }
        {
          kind = "host";
          name = "web01";
          tenant = "admin";
        }
      ];
    };

    communicationContract = {

      trafficTypes = [
        {
          name = "any";
          match = [
            {
              proto = "any";
              family = "any";
            }
          ];
        }
      ];

      services = [ ];

      relations = [

        {
          id = "allow-tenants-to-wan";
          priority = 1;

          from = {
            kind = "tenant-set";
            members = [
              "mgmt"
              "admin"
              "client"
            ];
          };

          to = {
            kind = "external";
            name = "wan";
          };

          trafficType = "any";
          action = "allow";
        }

        {
          id = "allow-wan-to-tenants";
          priority = 2;

          from = {
            kind = "external";
            name = "wan";
          };

          to = {
            kind = "tenant-set";
            members = [
              "mgmt"
              "admin"
              "client"
            ];
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
