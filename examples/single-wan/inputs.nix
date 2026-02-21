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
          }
          {
            name = "clients";
            ipv4 = "10.20.20.0/24";
            ipv6 = "fd42:dead:beef:20::/64";
          }
        ];

        services = [
          {
            name = "dns";
            prefixes = [
              "10.20.10.53/32"
              "fd42:dead:beef:10::53/128"
            ];
          }
          {
            name = "ntp";
            prefixes = [ "10.20.10.123/32" ];
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
          from = "tenants:clients";
          to = "services:dns";
          proto = [
            "udp/53"
            "tcp/53"
          ];
          action = "allow";
        }
        {
          from = "tenants:clients";
          to = "external:default";
          action = "allow";
        }
        {
          from = "tenants:clients";
          to = "tenants:mgmt";
          action = "deny";
        }
      ];
    };

    nodes = {
      s-router-core = {
        role = "core";
        isp = { };
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
