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
        name = "hostile";
        ipv4 = "10.20.10.0/24";
        ipv6 = "fd42:dead:beef:10::/64";
      }
      {
        kind = "tenant";
        name = "client";
        ipv4 = "10.20.20.0/24";
        ipv6 = "fd42:dead:beef:20::/64";
      }
    ];

    communicationContract = {
      trafficTypes = [
        {
          name = "nebula";
          match = [
            {
              proto = "udp";
              dports = [ 4242 ];
              family = "any";
            }
          ];
        }
      ];
      services = [ ];
      relations = [
        {
          id = "allow-hostile-to-overlay";
          priority = 100;
          from = {
            kind = "tenant";
            name = "hostile";
          };
          to = {
            kind = "external";
            name = "east-west";
          };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "allow-client-underlay-to-wan";
          priority = 105;
          from = {
            kind = "tenant";
            name = "client";
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "any";
          action = "allow";
        }
        {
          id = "allow-overlay-underlay-to-wan";
          priority = 110;
          from = {
            kind = "external";
            name = "east-west";
          };
          to = {
            kind = "external";
            name = "wan";
          };
          trafficType = "nebula";
          action = "allow";
        }
      ];
    };

    transport.overlays = [
      {
        name = "east-west";
        terminateOn = "core-overlay";
        underlayAccess = {
          kind = "tenant";
          name = "client";
        };
        underlayTrafficTypes = [ "nebula" ];
      }
    ];

    topology = {
      nodes = {
        core-wan = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
        core-overlay = {
          role = "core";
          attachments = [
            {
              kind = "tenant";
              name = "client";
            }
          ];
          uplinks.east-west.ipv4 = [ "100.96.20.0/24" ];
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
        access-hostile = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "hostile";
            }
          ];
        };
        access-client = {
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
          "core-wan"
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
          "access-hostile"
        ]
        [
          "downstream"
          "access-client"
        ]
      ];
    };
  };
}
