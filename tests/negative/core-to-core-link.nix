{
  badsite = {
    pools = {
      p2p.ipv4 = "10.10.0.0/24";
      loopback.ipv4 = "10.19.0.0/24";
    };

    ownership.prefixes = [
      {
        kind = "tenant";
        name = "mgmt";
        ipv4 = "10.20.10.0/24";
      }
    ];

    communicationContract = {
      trafficTypes = [ ];
      services = [ ];
      relations = [
        {
          id = "allow-mgmt-to-wan";
          priority = 100;
          from = { kind = "tenant"; name = "mgmt"; };
          to = { kind = "external"; uplinks = [ "wan" ]; };
          trafficType = "any";
          action = "allow";
        }
      ];
    };

    topology = {
      nodes = {
        core-wan = {
          role = "core";
          uplinks.wan.ipv4 = [ "0.0.0.0/0" ];
        };
        core-nebula = {
          role = "core";
          uplinks.east-west.ipv4 = [ "100.96.0.0/24" ];
        };
        upstream.role = "upstream-selector";
        policy.role = "policy";
        downstream.role = "downstream-selector";
        access = {
          role = "access";
          attachments = [ { kind = "tenant"; name = "mgmt"; } ];
        };
      };

      links = [
        [ "core-wan" "core-nebula" ]
        [ "core-wan" "upstream" ]
        [ "core-nebula" "upstream" ]
        [ "upstream" "policy" ]
        [ "policy" "downstream" ]
        [ "downstream" "access" ]
      ];
    };
  };
}
