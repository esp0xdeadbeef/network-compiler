{ lib }:

let
  eval = import ../lib/eval.nix { inherit lib; };

  baseInputs = {
    tenantVlans = [ 10 ];
    policyAccessTransitBase = 100;
    corePolicyTransitVlan = 200;
    ulaPrefix = "fd42:dead:beef";
    tenantV4Base = "10.10";
  };

in
{

  invalid-defaultRouteMode = eval {
    topology = import ../lib/topology-gen.nix { inherit lib; } (
      baseInputs
      // {
        defaultRouteMode = "broken-mode";
      }
    );
  };

  computed-without-wan = eval {
    topology = import ../lib/topology-gen.nix { inherit lib; } (
      baseInputs
      // {
        defaultRouteMode = "computed";
      }
    );
  };

  blackhole-with-wan-default = eval {
    topology = (import ../lib/topology-gen.nix { inherit lib; } baseInputs) // {
      defaultRouteMode = "blackhole";

      links.isp = {
        kind = "wan";
        vlanId = 6;
        carrier = "wan";
        members = [ "s-router-core-wan" ];
        endpoints."s-router-core-wan" = {
          addr6 = "2001:db8:1::2/48";
          routes6 = [ { dst = "::/0"; } ];
        };
      };
    };
  };

  default-mode-no-wan-default = eval {
    topology = (import ../lib/topology-gen.nix { inherit lib; } baseInputs) // {
      defaultRouteMode = "default";

      links.isp = {
        kind = "wan";
        vlanId = 6;
        carrier = "wan";
        members = [ "s-router-core-wan" ];
        endpoints."s-router-core-wan" = {
          addr6 = "2001:db8:1::2/48";
          routes6 = [ ];
        };
      };
    };
  };

  missing-policy-core = eval {
    topology =
      let
        t = import ../lib/topology-gen.nix { inherit lib; } baseInputs;
      in
      t
      // {
        links = builtins.removeAttrs t.links [ "policy-core" ];
      };
  };

  forbidden-vlan = eval {
    topology = import ../lib/topology-gen.nix { inherit lib; } (
      baseInputs
      // {
        tenantVlans = [ 5 ];
      }
    );
  };

  invalid-ipv4-cidr = eval {
    topology = (import ../lib/topology-gen.nix { inherit lib; } baseInputs) // {
      links.isp = {
        kind = "wan";
        vlanId = 6;
        carrier = "wan";
        members = [ "s-router-core-wan" ];
        endpoints."s-router-core-wan" = {
          addr4 = "300.0.0.1/24";
          routes4 = [ { dst = "300.0.0.0/24"; } ];
        };
      };
    };
  };

  invalid-ipv6-cidr = eval {
    topology = (import ../lib/topology-gen.nix { inherit lib; } baseInputs) // {
      links.isp = {
        kind = "wan";
        vlanId = 6;
        carrier = "wan";
        members = [ "s-router-core-wan" ];
        endpoints."s-router-core-wan" = {
          addr6 = "gggg::1/64";
        };
      };
    };
  };

  p2p-vlan-out-of-range = eval {
    topology = import ../lib/topology-gen.nix { inherit lib; } (
      baseInputs
      // {
        corePolicyTransitVlan = 300;
      }
    );
  };

}
