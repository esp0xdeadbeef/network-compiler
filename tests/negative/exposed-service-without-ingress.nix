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

    policy = {
      external = {
        wantDefault = true;
        wantFullTables = false;
      };

      catalog = {
        services = [
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
        ingress = [ ];
      };

      rules = [ ];
    };

    topology = {
      nodes = {
        s-router-core = {
          role = "core";
          nat = {
            mode = "custom";
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
