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
          name = "dns";
          match = [
            {
              proto = "udp";
              dports = [ 53 ];
              family = "any";
            }
            {
              proto = "tcp";
              dports = [ 53 ];
              family = "any";
            }
          ];
        }
        {
          name = "ssh";
          match = [
            {
              proto = "tcp";
              dports = [ 22 ];
              family = "any";
            }
          ];
        }
      ];

      services = [
        {
          name = "dns-site";
          trafficType = "dns";
          providers = [ ];
        }
        {
          name = "external-jump-host";
          trafficType = "ssh";
          providers = [ ];
        }
      ];

      relations = [
        {
          id = "allow-admin-to-mgmt-dns";
          priority = 100;
          from = {
            kind = "tenant";
            name = "admin";
          };
          to = {
            kind = "service";
            name = "dns-site";
          };
          trafficType = "dns";
          action = "allow";
        }
        {
          id = "deny-client-to-mgmt-dns";
          priority = 90;
          from = {
            kind = "tenant";
            name = "client";
          };
          to = {
            kind = "service";
            name = "dns-site";
          };
          trafficType = "dns";
          action = "deny";
        }
        {
          id = "allow-client-to-wan-any";
          priority = 200;
          from = {
            kind = "tenant";
            name = "client";
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "deny-client-to-mgmt";
          priority = 150;
          from = {
            kind = "tenant";
            name = "client";
          };
          to = {
            kind = "tenant";
            name = "mgmt";
          };
          trafficType = "any";
          action = "deny";
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
