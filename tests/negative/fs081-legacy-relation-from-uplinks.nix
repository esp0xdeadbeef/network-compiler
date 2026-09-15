let
  baseSite = {
    pools = {
      p2p.ipv4 = "10.10.0.0/24";
      p2p.ipv6 = "fd42:dead:beef:1000::/118";
      loopback.ipv4 = "10.19.0.0/24";
      loopback.ipv6 = "fd42:dead:beef:1900::/118";
    };
    ownership.prefixes = [
      {
        kind = "tenant";
        name = "mgmt";
        ipv4 = "10.20.10.0/24";
        ipv6 = "fd42:dead:beef:10::/64";
      }
    ];
    communicationContract = {
      trafficTypes = [ ];
      services = [ ];
      relations = [
        {
          id = "allow-mgmt-to-wan";
          priority = 100;
          from = {
            kind = "tenant";
            name = "mgmt";
          };
          to = {
            kind = "external";
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
          uplinks.wan = {
            ipv4 = [ "0.0.0.0/0" ];
            ipv6 = [ "::/0" ];
          };
        };
        upstream-selector = {
          role = "upstream-selector";
        };
        policy = {
          role = "policy";
        };
        downstream-selector = {
          role = "downstream-selector";
        };
        access = {
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
          "core"
          "upstream-selector"
        ]
        [
          "upstream-selector"
          "policy"
        ]
        [
          "policy"
          "downstream-selector"
        ]
        [
          "downstream-selector"
          "access"
        ]
      ];
    };
  };
in
{
  badsite = baseSite // {
    communicationContract = baseSite.communicationContract // {
      relations = [
        {
          id = "allow-wan-mgmt";
          priority = 90;
          from = {
            kind = "external";
            uplinks = [ "wan" ];
          };
          to = {
            kind = "tenant";
            name = "mgmt";
          };
          trafficType = "any";
          action = "allow";
        }
      ];
    };
  };
}
