{ lib }:

let
  coreNodeName = "s-router-core";
  policyNodeName = "s-router-policy-only";
  accessNodePrefix = "s-router-access";

  baseInput = {
    tenantVlans = [ 10 ];
    policyAccessTransitBase = 100;
    corePolicyTransitVlan = 200;
    ulaPrefix = "fd42:dead:beef";
    tenantV4Base = "10.10";

    inherit coreNodeName policyNodeName accessNodePrefix;
  };

  mkInput = attrs: baseInput // attrs;

  genTopo = attrs: import ../../lib/topology-gen.nix { inherit lib; } (mkInput attrs);

in
{

  invalid-defaultRouteMode = _: mkInput { defaultRouteMode = "broken-mode"; };

  computed-without-wan = _: mkInput { defaultRouteMode = "computed"; };

  blackhole-with-wan-default =
    _:
    let
      t = genTopo { };
    in
    t
    // {
      defaultRouteMode = "blackhole";
      links = (t.links or { }) // {
        isp = {
          kind = "wan";
          vlanId = 6;
          carrier = "wan";
          members = [ coreNodeName ];
          endpoints."${coreNodeName}" = {
            addr6 = "2001:db8:1::2/48";
            routes6 = [ { dst = "::/0"; } ];
          };
        };
      };
    };

  default-mode-no-wan-default =
    _:
    let
      t = genTopo { };
    in
    t
    // {
      defaultRouteMode = "default";
      links = (t.links or { }) // {
        isp = {
          kind = "wan";
          vlanId = 6;
          carrier = "wan";
          members = [ coreNodeName ];
          endpoints."${coreNodeName}" = {
            addr6 = "2001:db8:1::2/48";

          };
        };
      };
    };

  missing-policy-core =
    _:
    let
      t = genTopo { };
    in
    t
    // {
      links = builtins.removeAttrs (t.links or { }) [ "policy-core" ];
    };

  forbidden-vlan = _: mkInput { tenantVlans = [ 5 ]; };

  invalid-ipv4-cidr =
    _:
    let
      t = genTopo { };
    in
    t
    // {
      links = (t.links or { }) // {
        isp = {
          kind = "wan";
          vlanId = 6;
          carrier = "wan";
          members = [ coreNodeName ];
          endpoints."${coreNodeName}" = {
            addr4 = "300.0.0.1/24";
            routes4 = [ { dst = "300.0.0.0/24"; } ];
          };
        };
      };
    };

  invalid-ipv6-cidr =
    _:
    let
      t = genTopo { };
    in
    t
    // {
      links = (t.links or { }) // {
        isp = {
          kind = "wan";
          vlanId = 6;
          carrier = "wan";
          members = [ coreNodeName ];
          endpoints."${coreNodeName}" = {
            addr6 = "gggg::1/64";
          };
        };
      };
    };

  p2p-vlan-out-of-range = _: mkInput { corePolicyTransitVlan = 300; };
}
