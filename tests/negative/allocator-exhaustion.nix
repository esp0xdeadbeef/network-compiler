{
  badsite = {
    pools = {
      p2p = {

        ipv4 = "10.10.0.0/30";
        ipv6 = "fd42:dead:beef:1000::/126";
      };

      loopback = {
        ipv4 = "10.19.0.0/30";
        ipv6 = "fd42:dead:beef:1900::/126";
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
        services = [ ];
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
            mode = "none";
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
