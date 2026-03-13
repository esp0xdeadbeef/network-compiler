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
          name = "ntp";
          match = [
            {
              proto = "udp";
              dports = [ 123 ];
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
          name = "ntp-site";
          trafficType = "ntp";
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
          id = "deny-clients-to-mgmt-dns";
          priority = 90;
          from = {
            kind = "tenant";
            name = "clients";
          };
          to = {
            kind = "service";
            name = "dns-site";
          };
          trafficType = "dns";
          action = "deny";
        }
        {
          id = "allow-clients-to-wan-any";
          priority = 200;
          from = {
            kind = "tenant";
            name = "clients";
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "any";
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
          trafficType = "any";
          action = "deny";
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

        s-router-access-clients = {
          role = "access";
          attachments = [
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
          "s-router-access-mgmt"
        ]
        [
          "s-router-policy"
          "s-router-access-admin"
        ]
        [
          "s-router-policy"
          "s-router-access-clients"
        ]
      ];
    };
  };

  esp0xdeadbeef-2.site-b = {

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
      {
        kind = "tenant";
        name = "admin";
        ipv4 = "10.30.15.0/24";
        ipv6 = "fd42:dead:beef:15::/64";
      }
      {
        kind = "tenant";
        name = "clients";
        ipv4 = "10.30.20.0/24";
        ipv6 = "fd42:dead:beef:20::/64";
      }
    ];

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
          name = "ntp";
          match = [
            {
              proto = "udp";
              dports = [ 123 ];
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
          name = "ntp-site";
          trafficType = "ntp";
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
          id = "deny-clients-to-mgmt-dns";
          priority = 90;
          from = {
            kind = "tenant";
            name = "clients";
          };
          to = {
            kind = "service";
            name = "dns-site";
          };
          trafficType = "dns";
          action = "deny";
        }
        {
          id = "allow-clients-to-wan-any";
          priority = 200;
          from = {
            kind = "tenant";
            name = "clients";
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "any";
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
          trafficType = "any";
          action = "deny";
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

        s-router-access-clients = {
          role = "access";
          attachments = [
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
          "s-router-access-mgmt"
        ]
        [
          "s-router-policy"
          "s-router-access-admin"
        ]
        [
          "s-router-policy"
          "s-router-access-clients"
        ]
      ];
    };
  };
}
