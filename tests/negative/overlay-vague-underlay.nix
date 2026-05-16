{
  badsite = {
    pools = {
      p2p.ipv4 = "10.10.0.0/24";
      loopback.ipv4 = "10.19.0.0/24";
    };

    ownership.prefixes = [
      {
        kind = "tenant";
        name = "client";
        ipv4 = "10.20.10.0/24";
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
          id = "allow-client-to-east-west";
          priority = 100;
          from = {
            kind = "tenant";
            name = "client";
          };
          to = {
            kind = "external";
            name = "east-west";
          };
          trafficType = "any";
          action = "allow";
        }
      ];
    };

    transport.overlays = [
      {
        name = "east-west";
        peerSites = [ "good.remote" ];
        terminateOn = "overlay-core";
        mustTraverse = [ "policy" ];
      }
    ];

    topology = {
      nodes = {
        wan-core = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
        overlay-core = {
          role = "core";
          uplinks.east-west.ipv4 = [ "100.96.0.0/24" ];
        };
        upstream.role = "upstream-selector";
        policy.role = "policy";
        downstream.role = "downstream-selector";
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
        [ "wan-core" "upstream" ]
        [ "overlay-core" "upstream" ]
        [ "upstream" "policy" ]
        [ "policy" "downstream" ]
        [ "downstream" "access" ]
      ];
    };
  };
}
