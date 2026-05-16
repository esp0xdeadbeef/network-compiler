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
      trafficTypes = [ ];
      services = [ ];
      relations = [
        {
          id = "allow-overlay-to-wan-same-core";
          priority = 100;
          from = {
            kind = "external";
            name = "east-west";
          };
          to = {
            kind = "external";
            uplinks = [ "wan" ];
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
        terminateOn = "edge-core";
        mustTraverse = [ "policy" ];
      }
    ];

    topology = {
      nodes = {
        edge-core = {
          role = "core";
          uplinks = {
            east-west.ipv4 = [ "100.96.0.0/24" ];
            wan.ipv4 = [ "0.0.0.0/0" ];
          };
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
        [ "edge-core" "upstream" ]
        [ "upstream" "policy" ]
        [ "policy" "downstream" ]
        [ "downstream" "access" ]
      ];
    };
  };
}
