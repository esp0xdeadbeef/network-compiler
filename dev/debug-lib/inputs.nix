# ./dev/debug-lib/inputs.nix
#
# Debug / example inputs for nixos-network-compiler
#
# This file demonstrates how to control default route behaviour.
#
# -----------------------------------------------------------------------------
# defaultRouteMode
#
# Controls how "internet" routes are generated and installed.
#
#   "default"
#     - Access routers receive:
#         0.0.0.0/0
#         ::/0
#       via policy router.
#     - Policy router forwards these to core.
#     - WAN links may inject ::/0 or 0.0.0.0/0 if present.
#
#   "computed"
#     - Internet space is computed as:
#         universe (0/0, ::/0)
#         minus:
#           - RFC1918
#           - link-local
#           - ULA
#           - all prefixes owned by topology
#     - Results in many explicit prefixes instead of a single default.
#     - No blackholing occurs.
#
#   "blackhole"
#     - No default routes are installed on access routers.
#     - Only explicit tenant + internal routes exist.
#     - Effectively isolates tenants from internet.
#     - Useful for lab / containment / test fabrics.
#
# -----------------------------------------------------------------------------
#
# Examples:
#
#   defaultRouteMode = "default";   # simple default route
#   defaultRouteMode = "computed";  # decomposed internet space
#   defaultRouteMode = "blackhole"; # no internet routing
#
# -----------------------------------------------------------------------------
{
  sopsData ? { },
}:

let
  base = {
    tenantVlans = [
      10
      20
      30
      40
      50
      60
      70
      80
    ];

    ulaPrefix = "fd42:dead:beef";
    tenantV4Base = "10.10";

    policyAccessTransitBase = 100;
    policyAccessOffset = 0;

    corePolicyTransitVlan = 200;

    # -------------------------------------------------------------------------
    # DEFAULT ROUTE BEHAVIOUR
    #
    # Choose one:
    #
    #   "default"   → install 0.0.0.0/0 and ::/0
    #   "computed"  → derive internet space via CIDR subtraction
    #   "blackhole" → no default routes
    #
    # -------------------------------------------------------------------------
    defaultRouteMode = "default";

    links = {
      isp-1 = {
        kind = "wan";
        carrier = "wan";
        vlanId = 6;
        name = "isp-1";
        members = [ "s-router-core-wan" ];
        endpoints = {
          "s-router-core-wan" = {
            addr6 = "2001:db8:1::2/48";

            # Default routes only injected when in "default" mode
            routes6 =
              if base.defaultRouteMode == "default" then
                [
                  { dst = "::/0"; }
                ]
              else
                [ ];
          };
        };
      };

      isp-2 = {
        kind = "wan";
        carrier = "wan";
        vlanId = 7;
        name = "isp-2";
        members = [ "s-router-core-wan" ];
        endpoints = {
          "s-router-core-wan" = {
            addr6 = "2001:db8:2::2/48";

            routes6 =
              if base.defaultRouteMode == "default" then
                [
                  { dst = "::/0"; }
                ]
              else
                [ ];
          };
        };
      };

      nebula = {
        kind = "wan";
        carrier = "wan";
        vlanId = 8;
        name = "nebula";
        members = [ "s-router-core-wan" ];
        endpoints = {
          "s-router-core-wan" = {
            addr4 = "100.64.10.2/32";

            routes4 =
              if base.defaultRouteMode == "default" then
                [
                  { dst = "0.0.0.0/0"; }
                ]
              else
                [ ];
          };
        };
      };
    };
  };
in
base // sopsData
