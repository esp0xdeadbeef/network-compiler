{
  default = {
    stable = {
      enterprise = "default";
      siteName = "stable";

      ownership.prefixes = [
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

      pools = {
        loopback = {
          ipv4 = "10.19.0.0/24";
          ipv6 = "fd42:dead:beef:1900::/118";
        };
        p2p = {
          ipv4 = "10.10.0.0/24";
          ipv6 = "fd42:dead:beef:1000::/118";
        };
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
        ];

        services = [
          {
            name = "dns-site";
            trafficType = "dns";
            providers = [ ];
          }
        ];

        relations = [
          {
            id = "first-same-priority";
            action = "allow";
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
          }
          {
            id = "second-same-priority";
            action = "deny";
            priority = 100;
            from = {
              kind = "tenant";
              name = "clients";
            };
            to = {
              kind = "service";
              name = "dns-site";
            };
            trafficType = "dns";
          }
          {
            id = "allow-admin-to-wan";
            action = "allow";
            priority = 200;
            from = {
              kind = "tenant";
              name = "admin";
            };
            to = {
              kind = "external";
              name = "wan";
            };
            trafficType = "any";
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
            "s-router-policy"
          ]
          [
            "s-router-policy"
            "s-router-access"
          ]
        ];
      };
    };
  };
}
