{ lib }:

let
  mkBase =
    attrs:
    import ../../lib/topology-gen.nix { inherit lib; } (
      {
        tenantVlans = [ 10 ];
        policyAccessTransitBase = 100;
        corePolicyTransitVlan = 200;
        ulaPrefix = "fd42:dead:beef";
        tenantV4Base = "10.10";
      }
      // attrs
    );

in
{

  invalid-defaultRouteMode = mkBase { defaultRouteMode = "broken-mode"; };

  computed-without-wan = mkBase { defaultRouteMode = "computed"; };

  blackhole-with-wan-default = (mkBase { }) // {
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

  default-mode-no-wan-default = (mkBase { }) // {
    defaultRouteMode = "default";
    links.isp = {
      kind = "wan";
      vlanId = 6;
      carrier = "wan";
      members = [ "s-router-core-wan" ];
      endpoints."s-router-core-wan".addr6 = "2001:db8:1::2/48";
    };
  };

  missing-policy-core =
    let
      t = mkBase { };
    in
    t // { links = builtins.removeAttrs t.links [ "policy-core" ]; };

  forbidden-vlan = mkBase { tenantVlans = [ 5 ]; };

  invalid-ipv4-cidr = (mkBase { }) // {
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

  invalid-ipv6-cidr = (mkBase { }) // {
    links.isp = {
      kind = "wan";
      vlanId = 6;
      carrier = "wan";
      members = [ "s-router-core-wan" ];
      endpoints."s-router-core-wan".addr6 = "gggg::1/64";
    };
  };

  p2p-vlan-out-of-range = mkBase { corePolicyTransitVlan = 300; };
}
