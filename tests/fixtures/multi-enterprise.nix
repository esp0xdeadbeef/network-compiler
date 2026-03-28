{
  alpha = {
    "site-a" = {
      pools = {
        p2p = {
          ipv4 = "10.40.0.0/24";
          ipv6 = "fd42:dead:beef:4000::/118";
        };
        loopback = {
          ipv4 = "10.49.0.0/24";
          ipv6 = "fd42:dead:beef:4900::/118";
        };
      };

      ownership.prefixes = [
        {
          kind = "tenant";
          name = "mgmt";
          ipv4 = "10.40.10.0/24";
          ipv6 = "fd42:dead:beef:40::/64";
        }
      ];

      communicationContract = {
        trafficTypes = [ ];
        services = [ ];
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
  };

  bravo = {
    "site-a" = {
      pools = {
        p2p = {
          ipv4 = "10.50.0.0/24";
          ipv6 = "fd42:dead:beef:5000::/118";
        };
        loopback = {
          ipv4 = "10.59.0.0/24";
          ipv6 = "fd42:dead:beef:5900::/118";
        };
      };

      ownership.prefixes = [
        {
          kind = "tenant";
          name = "adm";
          ipv4 = "10.50.10.0/24";
          ipv6 = "fd42:dead:beef:50::/64";
        }
      ];

      communicationContract = {
        trafficTypes = [ ];
        services = [ ];
        relations = [
          {
            id = "allow-adm-to-uplink1";
            priority = 100;
            from = {
              kind = "tenant";
              name = "adm";
            };
            to = {
              kind = "external";
              uplinks = [ "uplink1" ];
            };
            trafficType = "any";
            action = "allow";
          }
        ];
      };

      topology = {
        nodes = {
          s-router-core = {
            role = "core";
            uplinks = {
              uplink1 = {
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
                name = "adm";
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
