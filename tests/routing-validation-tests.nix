# This file contains NEGATIVE test cases that are expected to FAIL.
# Each test documents the exact IPv4/IPv6 routing validation error
# and explains why the failure is correct.
#
# These tests intentionally trigger assertions or throws inside:
#
#   - compile/assertions/pre.nix
#   - compile/assertions/post.nix
#   - compile/assertions/default-route-mode.nix
#   - compile/assertions/default-route-wan-consistency.nix
#   - compile/validate.nix
#   - model/addressing.nix
#
# Every test explains the expected failure inside comments.
#

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

  ###########################################################################
  # 1. INVALID defaultRouteMode VALUE
  #
  # Expected failure:
  #   compile/assertions/pre.nix
  #
  # Reason:
  #   defaultRouteMode must be one of:
  #     "default", "computed", "blackhole"
  ###########################################################################
  invalid-defaultRouteMode = eval {
    topology = import ../lib/topology-gen.nix { inherit lib; } (
      baseInputs
      // {
        defaultRouteMode = "broken-mode"; # ❌ INVALID VALUE
      }
    );
  };

  ###########################################################################
  # 2. COMPUTED MODE WITHOUT ANY WAN LINK
  #
  # Expected failure:
  #   compile/assertions/default-route-mode.nix
  #
  # Reason:
  #   defaultRouteMode = "computed"
  #   requires at least one WAN link to derive public internet space.
  ###########################################################################
  computed-without-wan = eval {
    topology = import ../lib/topology-gen.nix { inherit lib; } (
      baseInputs
      // {
        defaultRouteMode = "computed"; # ❌ No WAN links defined
      }
    );
  };

  ###########################################################################
  # 3. BLACKHOLE MODE BUT WAN ADVERTISES DEFAULT ROUTE
  #
  # Expected failure:
  #   compile/assertions/default-route-wan-consistency.nix
  #
  # Reason:
  #   In blackhole mode, WAN endpoints MUST NOT advertise:
  #     0.0.0.0/0 or ::/0
  ###########################################################################
  blackhole-with-wan-default = eval {
    topology = (import ../lib/topology-gen.nix { inherit lib; } baseInputs) // {
      defaultRouteMode = "blackhole";

      # ❌ WAN incorrectly injects default route
      links.isp = {
        kind = "wan";
        vlanId = 6;
        carrier = "wan";
        members = [ "s-router-core-wan" ];
        endpoints."s-router-core-wan" = {
          addr6 = "2001:db8:1::2/48";
          routes6 = [ { dst = "::/0"; } ]; # ❌ NOT ALLOWED in blackhole
        };
      };
    };
  };

  ###########################################################################
  # 4. DEFAULT MODE BUT NO WAN PROVIDES DEFAULT ROUTE
  #
  # Expected failure:
  #   compile/assertions/default-route-wan-consistency.nix
  #
  # Reason:
  #   In "default" mode, at least one WAN must advertise:
  #     0.0.0.0/0 or ::/0
  ###########################################################################
  default-mode-no-wan-default = eval {
    topology = (import ../lib/topology-gen.nix { inherit lib; } baseInputs) // {
      defaultRouteMode = "default";

      # ❌ WAN exists but does NOT advertise default
      links.isp = {
        kind = "wan";
        vlanId = 6;
        carrier = "wan";
        members = [ "s-router-core-wan" ];
        endpoints."s-router-core-wan" = {
          addr6 = "2001:db8:1::2/48";
          routes6 = [ ]; # ❌ missing ::/0
        };
      };
    };
  };

  ###########################################################################
  # 5. MISSING policy-core LINK
  #
  # Expected failure:
  #   compile/assertions/post.nix
  #
  # Reason:
  #   policy-core p2p link is REQUIRED between:
  #     s-router-policy-only
  #     s-router-core-wan
  ###########################################################################
  missing-policy-core = eval {
    topology =
      let
        t = import ../lib/topology-gen.nix { inherit lib; } baseInputs;
      in
      t
      // {
        links = builtins.removeAttrs t.links [ "policy-core" ]; # ❌ removed
      };
  };

  ###########################################################################
  # 6. FORBIDDEN VLAN RANGE
  #
  # Expected failure:
  #   compile/validate.nix
  #
  # Reason:
  #   VLANs 2..9 are forbidden by default.
  ###########################################################################
  forbidden-vlan = eval {
    topology = import ../lib/topology-gen.nix { inherit lib; } (
      baseInputs
      // {
        tenantVlans = [ 5 ]; # ❌ VLAN 5 is forbidden
      }
    );
  };

  ###########################################################################
  # 7. INVALID IPv4 CIDR IN WAN ROUTE
  #
  # Expected failure:
  #   cidr-substract.nix (parseCidr4)
  #
  # Reason:
  #   "300.0.0.0/24" is not a valid IPv4 address.
  ###########################################################################
  invalid-ipv4-cidr = eval {
    topology = (import ../lib/topology-gen.nix { inherit lib; } baseInputs) // {
      links.isp = {
        kind = "wan";
        vlanId = 6;
        carrier = "wan";
        members = [ "s-router-core-wan" ];
        endpoints."s-router-core-wan" = {
          addr4 = "300.0.0.1/24"; # ❌ invalid IPv4 octet
          routes4 = [ { dst = "300.0.0.0/24"; } ];
        };
      };
    };
  };

  ###########################################################################
  # 8. INVALID IPv6 CIDR IN WAN ROUTE
  #
  # Expected failure:
  #   cidr-subtract-v6.nix (parseCidr6)
  #
  # Reason:
  #   "gggg::/64" is not valid hexadecimal IPv6.
  ###########################################################################
  invalid-ipv6-cidr = eval {
    topology = (import ../lib/topology-gen.nix { inherit lib; } baseInputs) // {
      links.isp = {
        kind = "wan";
        vlanId = 6;
        carrier = "wan";
        members = [ "s-router-core-wan" ];
        endpoints."s-router-core-wan" = {
          addr6 = "gggg::1/64"; # ❌ invalid IPv6
        };
      };
    };
  };

  ###########################################################################
  # 9. P2P VLAN OUT OF RANGE FOR IPv6 TRANSIT
  #
  # Expected failure:
  #   model/addressing.nix → transitHextet
  #
  # Reason:
  #   transit VLAN must be 0..255
  ###########################################################################
  p2p-vlan-out-of-range = eval {
    topology = import ../lib/topology-gen.nix { inherit lib; } (
      baseInputs
      // {
        corePolicyTransitVlan = 300; # ❌ >255 not allowed for p2p transit
      }
    );
  };

}
