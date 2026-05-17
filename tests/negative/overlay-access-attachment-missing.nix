{
  esp = {
    site-a = {
      pools.p2p.ipv4 = "10.10.0.0/24";
      pools.loopback.ipv4 = "10.19.0.0/24";

      ownership.prefixes = [
        {
          kind = "tenant";
          name = "client";
          ipv4 = "10.20.20.0/24";
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
        relations = [
          {
            id = "allow-empty-tenant-set-to-overlay";
            priority = 90;
            from = {
              kind = "tenant-set";
              members = [ ];
            };
            to = {
              kind = "external";
              name = "east-west";
            };
            trafficType = "any";
            action = "allow";
          }
          {
            id = "allow-overlay-underlay-to-wan";
            priority = 100;
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
          peerSite = "esp.site-b";
          terminateOn = "core-overlay";
          mustTraverse = [ "policy" ];
        }
      ];

      topology.nodes = {
        access = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "client";
            }
          ];
        };
        downstream.role = "downstream-selector";
        policy.role = "policy";
        upstream.role = "upstream-selector";
        core-wan = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
        core-overlay = {
          role = "core";
          uplinks.east-west.ipv4 = [ "100.96.0.0/24" ];
        };
      };

      topology.links = [
        [
          "core-wan"
          "upstream"
        ]
        [
          "core-overlay"
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
