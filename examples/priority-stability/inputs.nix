{
  default = {
    stable = {
      enterprise = "default";
      siteName = "stable";

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

      policy = {
        catalog.services = [
          {
            kind = "service";
            name = "dns-site";
            scope = "site";
            provides = [ "resolver" ];
            zoneHint = {
              kind = "tenant";
              name = "mgmt";
            };
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
          }
        ];

        external = {
          wantDefault = false;
          wantFullTables = false;
        };

        nat.ingress = [ ];

        rules = [
          {
            id = "first-same-priority";
            action = "allow";
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
              kind = "tenant";
              name = "mgmt";
              capability = "resolver";
            };
          }
        ];
      };

      topology = {
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

        nodes = {
          s-router-core = {
            role = "core";
            nat.mode = "custom";
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
      };
    };
  };
}
