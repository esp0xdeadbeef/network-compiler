{
  esp0xdeadbeef = {
    "site-a" = {
      pools.p2p.ipv4 = "10.10.0.0/24";
      pools.loopback.ipv4 = "10.19.0.0/24";

      ownership = {
        prefixes = [
          {
            kind = "tenant";
            name = "client";
            ipv4 = "10.20.20.0/24";
          }
        ];
        endpoints = [
          {
            kind = "service";
            name = "access-dns";
            tenant = "client";
          }
        ];
      };

      communicationContract = {
        trafficTypes = [
          {
            name = "dns";
            match = [
              {
                family = "ipv4";
                proto = "udp";
                dports = [ 53 ];
              }
            ];
          }
          {
            name = "ipv4-any";
            match = [
              {
                family = "ipv4";
                proto = "any";
              }
            ];
          }
        ];
        services = [
          {
            name = "access-dns";
            providers = [ "access-dns" ];
            trafficType = "dns";
          }
        ];
        relations = [
          {
            id = "allow-client-to-uplink0";
            priority = 90;
            from = {
              kind = "tenant";
              name = "client";
            };
            to = {
              kind = "external";
              uplinks = [ "uplink0" ];
            };
            trafficType = "ipv4-any";
            action = "allow";
          }
          {
            id = "allow-client-to-access-dns";
            priority = 100;
            from = {
              kind = "tenant";
              name = "client";
            };
            to = {
              kind = "service";
              name = "access-dns";
            };
            trafficType = "dns";
            action = "allow";
          }
        ];
      };

      topology.nodes = {
        access-client = {
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
        core = {
          role = "core";
          uplinks.uplink0.ipv4 = [ "0.0.0.0/0" ];
        };
      };

      topology.links = [
        [
          "access-client"
          "downstream"
        ]
        [
          "downstream"
          "policy"
        ]
        [
          "policy"
          "upstream"
        ]
        [
          "upstream"
          "core"
        ]
      ];
    };
  };
}
