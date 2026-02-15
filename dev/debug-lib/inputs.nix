# FILE: ./dev/debug-lib/inputs.nix
{
  sopsData ? { },
}:

let
  base = rec {
    tenantVlans = [
      10 20 30 40 50 60 70 80
    ];

    ulaPrefix = "fd42:dead:beef";
    tenantV4Base = "10.10";

    policyAccessTransitBase = 100;
    policyAccessOffset = 0;

    corePolicyTransitVlan = 200;

    # fabric host (bridge box)
    policyNodeName = "s-router-policy-only";
    coreNodeName = "s-router-core";

    defaultRouteMode = "default";

    # Optional: pick which routing-context node should be "core" for policy-core routing.
    # If unset, routing-gen will try "${coreNodeName}-wan", else auto-pick a unique "${coreNodeName}-*".
    # coreRoutingNodeName = "${coreNodeName}-isp-1";

    links = {
      isp-1 = {
        kind = "wan";
        carrier = "wan";
        vlanId = 4;
        name = "isp-1";
        members = [ coreNodeName ];
        endpoints = {
          "${coreNodeName}-isp-1" = {
            addr4 = "10.11.0.40/24";
            addr6 = "fd11:dead:beef:0::1337/64";
            routes4 = [ { dst = "0.0.0.0/0"; } ];
            routes6 = [ { dst = "::/0"; } ];
          };
        };
      };

      isp-2 = {
        kind = "wan";
        carrier = "wan";
        vlanId = 7;
        name = "isp-2";
        members = [ coreNodeName ];
        endpoints = {
          "${coreNodeName}-isp-2" = {
            addr4 = "10.13.0.40/24";
            addr6 = "fd13:dead:beef:0::1337/64";
            routes4 = [ { dst = "0.0.0.0/0"; } ];
            routes6 = [ { dst = "::/0"; } ];
          };
        };
      };

      nebula = {
        kind = "wan";
        carrier = "wan";
        vlanId = 8;
        name = "nebula";
        members = [ coreNodeName ];
        endpoints = {
          "${coreNodeName}-nebula" = {
            addr4 = "100.64.10.2/32";

            routes4 =
              if defaultRouteMode == "default" then
                [ { dst = "0.0.0.0/0"; } ]
              else
                [ ];
          };
        };
      };
    };
  };
in
base // sopsData

