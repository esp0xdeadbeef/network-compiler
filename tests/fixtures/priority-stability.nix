{
  esp0xdeadbeef = {
    "site-a" = {
      pools = {
        p2p = {
          ipv4 = "10.60.0.0/24";
          ipv6 = "fd42:dead:beef:6000::/118";
        };
        loopback = {
          ipv4 = "10.69.0.0/24";
          ipv6 = "fd42:dead:beef:6900::/118";
        };
      };

      ownership.prefixes = [
        {
          kind = "tenant";
          name = "mgmt";
          ipv4 = "10.60.10.0/24";
          ipv6 = "fd42:dead:beef:60::/64";
        }
      ];

      communicationContract = {
        trafficTypes = [
          {
            name = "tcp22";
            match = [
              {
                proto = "tcp";
                family = "any";
                dports = [ 22 ];
              }
            ];
          }
          {
            name = "udp53";
            match = [
              {
                proto = "udp";
                family = "any";
                dports = [ 53 ];
              }
            ];
          }
        ];

        services = [
          {
            name = "ssh";
            trafficType = "tcp22";
          }
          {
            name = "dns";
            trafficType = "udp53";
          }
        ];

        relations = [
          {
            id = "allow-mgmt-to-uplink0";
            priority = 100;
            from = {
              kind = "tenant";
              name = "mgmt";
            };
            to = {
              kind = "external";
              uplinks = [ "uplink0" ];
            };
            trafficType = "any";
            action = "allow";
          }
          {
            id = "allow-uplink0-to-dns";
            priority = 200;
            from = {
              kind = "external";
              uplinks = [ "uplink0" ];
            };
            to = {
              kind = "service";
              name = "dns";
            };
            trafficType = "udp53";
            action = "allow";
          }
          {
            id = "allow-uplink0-to-ssh";
            priority = 200;
            from = {
              kind = "external";
              uplinks = [ "uplink0" ];
            };
            to = {
              kind = "service";
              name = "ssh";
            };
            trafficType = "tcp22";
            action = "allow";
          }
        ];
      };

      topology = {
        nodes = {
          s-router-core = {
            role = "core";
            uplinks = {
              uplink0 = {
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

          s-router-downstream-selector = {
            role = "downstream-selector";
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
            "s-router-upstream-selector"
          ]
          [
            "s-router-upstream-selector"
            "s-router-policy"
          ]
          [
            "s-router-policy"
            "s-router-downstream-selector"
          ]
          [
            "s-router-downstream-selector"
            "s-router-access"
          ]
        ];
      };
    };
  };
}
