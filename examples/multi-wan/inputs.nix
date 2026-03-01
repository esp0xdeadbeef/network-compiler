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

    ownership.prefixes = [
      {
        kind = "tenant";
        name = "mgmt";
        ipv4 = "10.20.10.0/24";
        ipv6 = "fd42:dead:beef:20::/64";
      }
      {
        kind = "tenant";
        name = "adm";
        ipv4 = "10.21.10.0/24";
        ipv6 = "fd42:dead:beef:21::/64";
      }
    ];

    policy = {
      external.wantDefault = true;
      external.wantFullTables = false;
      catalog.services = [ ];
      nat.ingress = [ ];
      rules = [ ];
    };

    topology = {
      nodes = {
        s-router-core-isp-a = {
          role = "core";
          upstreams = {
            default = { };
          };
        };
        s-router-core-isp-b = {
          role = "core";
          upstreams = {
            default = { };
          };
        };

        s-router-upstream-selector = {
          role = "upstream-selector";
        };
        s-router-policy = {
          role = "policy";
        };
        s-router-access-adm = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "adm";
            }
          ];
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
      };

      links = [
        [
          "s-router-core-isp-a"
          "s-router-upstream-selector"
        ]
        [
          "s-router-core-isp-b"
          "s-router-upstream-selector"
        ]
        [
          "s-router-upstream-selector"
          "s-router-policy"
        ]
        [
          "s-router-policy"
          "s-router-access-adm"
        ]
        [
          "s-router-policy"
          "s-router-access-mgmt"
        ]
      ];
    };
  };

  esp0xdeadbeef.site-b = {

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
      rules = [ ];
    };

    topology = {
      nodes = {
        s-router-core-isp-a = {
          role = "core";
          upstreams = {
            default = { };
          };
        };
        s-router-core-isp-b = {
          role = "core";
          upstreams = {
            default = { };
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
          "s-router-core-isp-a"
          "s-router-upstream-selector"
        ]
        [
          "s-router-core-isp-b"
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
