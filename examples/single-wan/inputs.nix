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
          name = "clients";
          ipv4 = "10.20.20.0/24";
          ipv6 = "fd42:dead:beef:20::/64";
        }
      ];
    };

    policy = {

      external = {
        wantDefault = true;
        wantFullTables = false;
      };

      catalog = {

        services = [
          {
            kind = "service";
            name = "dns-site";
            match = [
              {
                l4 = "udp";
                dports = [ 53 ];
                families = [
                  "ipv4"
                  "ipv6"
                ];
              }
              {
                l4 = "tcp";
                dports = [ 53 ];
                families = [
                  "ipv4"
                  "ipv6"
                ];
              }
            ];
            scope = "site";
            zoneHint = {
              kind = "tenant";
              name = "mgmt";
            };
            provides = [ "resolver" ];
          }

          {
            kind = "service";
            name = "external-jump-host";
            match = [
              {
                l4 = "tcp";
                dports = [ 22 ];
                families = [
                  "ipv4"
                  "ipv6"
                ];
              }
            ];
            scope = "site";
            exposure = {
              external = true;
            };
            zoneHint = {
              kind = "tenant";
              name = "mgmt";
            };
          }
        ];
      };

      nat = {
        ingress = [
          {
            fromExternal = "default";
            toService = {
              kind = "service";
              name = "external-jump-host";
            };
          }
        ];
      };

      rules = [
        {
          id = "allow-admin-to-mgmt-dns";
          priority = 100;
          from = {
            kind = "tenant";
            name = "admin";
          };
          to = {
            kind = "tenant";
            name = "mgmt";
            capability = "resolver";
          };
          action = "allow";
        }

        {
          id = "deny-clients-to-mgmt-dns";
          priority = 90;
          from = {
            kind = "tenant";
            name = "clients";
          };
          to = {
            kind = "tenant";
            name = "mgmt";
            capability = "resolver";
          };
          action = "deny";
        }

        {
          id = "allow-clients-to-external-any";
          priority = 200;
          from = {
            kind = "tenant";
            name = "clients";
          };
          to = {
            external = "default";
          };
          proto = [ "any" ];
          action = "allow";
        }

        {
          id = "deny-clients-to-mgmt";
          priority = 150;
          from = {
            kind = "tenant";
            name = "clients";
          };
          to = {
            kind = "tenant";
            name = "mgmt";
          };
          action = "deny";
        }
      ];
    };

    topology = {
      nodes = {
        s-router-core = {
          role = "core";
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
            {
              kind = "tenant";
              name = "admin";
            }
            {
              kind = "tenant";
              name = "clients";
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
