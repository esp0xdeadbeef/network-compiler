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
        ipv4 = "10.20.20.0/24";
      }
    ];

    communicationContract = {
      trafficTypes = [ ];
      services = [ ];
      relations = [
        {
          id = "allow-client-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "client"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
      ];
    };

    topology = {
      nodes = {
        core = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
        upstream.role = "upstream-selector";
        policy.role = "policy";
        downstream.role = "downstream-selector";
        access = {
          role = "access";
          attachments = [{ kind = "tenant"; name = "client"; }];
        };
      };

      links = [
        [ "core" "upstream" ]
        [ "upstream" "policy" ]
        [ "policy" "downstream" ]
        [ "downstream" "access" ]
        [ "downstream" "core" ]
      ];
    };
  };
}
