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

    ownership.prefixes = [
      {
        kind = "tenant";
        name = "client";
        ipv4 = "10.20.20.0/24";
        ipv6 = "fd42:dead:beef:20::/64";
      }
    ];

    localDnsSharingIntent = [
      {
        namespace = "lan.";
        relation = {
          id = "allow-vlan3-dns-to-vlan2-dns";
          from = {
            kind = "service";
            name = "vlan3-dns";
          };
          to = {
            kind = "service";
            name = "vlan2-dns";
          };
          trafficType = "dns";
          returnBehavior = "symmetric";
          resolverPath = [
            "access-vlan3"
            "downstream-selector"
            "access-vlan2"
          ];
        };
      }
    ];

    communicationContract = {
      trafficTypes = [ ];
      services = [ ];
      relations = [
        {
          id = "allow-client-to-uplink0";
          priority = 100;
          from = {
            kind = "tenant";
            name = "client";
          };
          to = {
            kind = "external";
            scope = "uplink0";
          };
          trafficType = "any";
          action = "allow";
        }
      ];
    };

    topology = {
      nodes = {
        core = {
          role = "core";
          uplinks.uplink0 = {
            ipv4 = [ "0.0.0.0/0" ];
            ipv6 = [ "::/0" ];
          };
        };
        upstream = {
          role = "upstream-selector";
        };
        policy = {
          role = "policy";
        };
        downstream = {
          role = "downstream-selector";
        };
        access = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "client";
            }
          ];
        };
      };
      links = [
        [
          "core"
          "upstream"
        ]
        [
          "upstream"
          "policy"
        ]
        [
          "policy"
          "downstream"
        ]
        [
          "downstream"
          "access"
        ]
      ];
    };
  };
}
