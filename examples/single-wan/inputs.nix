{
  esp0xdeadbeef.site-a = {

    p2p-pool = {
      ipv4 = "10.10.0.0/24";
      ipv6 = "fd42:dead:beef:1000::/118";
    };

    processCell = {

      owned = {

        tenants = [

          {
            name = "mgmt";
            ipv4 = "10.20.10.0/24";
            ipv6 = "fd42:dead:beef:10::/64";

            exports = {
              resolver = { };
              ntp = { };
            };
          }

          {
            name = "admin";
            ipv4 = "10.20.15.0/24";
            ipv6 = "fd42:dead:beef:15::/64";
          }

          {
            name = "clients";
            ipv4 = "10.20.20.0/24";
            ipv6 = "fd42:dead:beef:20::/64";
          }
        ];
      };

      external = {
        wantDefault = true;
        wantFullTables = false;
      };

      authority = {
        internalRib = "s-router-policy";
        externalRib = "s-router-upstream-selector";
      };

      transitForwarder = {
        sink = "s-router-upstream-selector";
        mustRejectOwnedPrefixes = true;
      };

      policyIntent = [

        {
          from = {
            tenant = "admin";
          };
          to = {
            tenant = "mgmt";
            capability = "resolver";
          };
          proto = [
            "udp/53"
            "tcp/53"
          ];
          action = "allow";
        }

        {
          from = {
            tenant = "clients";
          };
          to = {
            tenant = "mgmt";
            capability = "resolver";
          };
          action = "deny";
        }

        {
          from = {
            tenant = "clients";
          };
          to = {
            external = "default";
          };
          proto = [ "any" ];
          action = "allow";
        }

        {
          from = {
            tenant = "clients";
          };
          to = {
            tenant = "mgmt";
          };
          action = "deny";
        }
      ];
    };

    nodes = {

      s-router-core = {
        role = "core";

        isp = {
          snat = true;
          nat = true;
          forwardPorts = [
            {
              port = 22;
              target = "s-infra-external-jump-host";
              ipv4 = true;
              ipv6 = true;
            }
          ];
        };

        vpn = { };
      };

      s-router-upstream-selector = {
        role = "upstream-selector";
      };

      s-router-policy = {
        role = "policy";
      };

      s-router-access = {
        role = "access";

        mgmt = {
          kind = "client";
          ipv4 = "10.20.10.0/24";
          ipv6 = "fd42:dead:beef:10::/64";
        };

        admin = {
          kind = "client";
          ipv4 = "10.20.15.0/24";
          ipv6 = "fd42:dead:beef:15::/64";
        };

        clients = {
          kind = "client";
          ipv4 = "10.20.20.0/24";
          ipv6 = "fd42:dead:beef:20::/64";
        };
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
}
