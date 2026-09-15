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
        core-a = {
          role = "core";
          uplinks.wan = {
            ipv4 = [ "0.0.0.0/0" ];
            ipv6 = [ "::/0" ];
          };
        };
        core-b = {
          role = "core";
          uplinks.backup = {
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
          selects = [
            "core-a"
            "core-b"
          ];
          behaviors = [ "not-a-behavior" ];
        };
      };
      links = [
        [
          "core-a"
          "upstream-selector"
        ]
        [
          "core-b"
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
  goodsite = baseSite;
}
