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
          {
            kind = "tenant";
            name = "dmz";
            ipv4 = "10.20.30.0/24";
          }
        ];
        endpoints = [ ];
      };

      communicationContract = {
        trafficTypes = [ ];
        services = [
          {
            name = "dns-dmz";
            providers = [ "dns-dmz01" ];
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
            trafficType = "any";
            action = "allow";
          }
          {
            id = "allow-client-to-dns";
            priority = 100;
            from = {
              kind = "tenant";
              name = "client";
            };
            to = {
              kind = "service";
              name = "dns-dmz";
            };
            trafficType = "any";
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
        access-dmz = {
          role = "access";
          attachments = [
            {
              kind = "tenant";
              name = "dmz";
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
          "access-dmz"
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
