# ./lib/eval.nix
# FILE: ./lib/eval.nix
{ lib }:

let
  mkWanLinks =
    coreNodeName: wan:
    if wan == null then
      { }
    else
      lib.mapAttrs (ctx: w:
        let
          coreCtx = "${coreNodeName}-${ctx}";
        in
        {
          kind = "wan";
          carrier = "wan";
          vlanId = w.vlanId or 6;
          name = "wan-${ctx}";

          # members can remain the fabric host; topology-resolve treats endpoint keys
          # as implicit members and creates the coreCtx node inheriting ifs.
          members = [ coreNodeName ];

          endpoints."${coreCtx}" =
            {
              routes4 = lib.optional (w ? ip4) { dst = "0.0.0.0/0"; };
              routes6 = lib.optional (w ? ip6) { dst = "::/0"; };
            }
            // lib.optionalAttrs (w ? ip4) { addr4 = w.ip4; }
            // lib.optionalAttrs (w ? ip6) { addr6 = w.ip6; }
            // lib.optionalAttrs (w ? acceptRA) { acceptRA = w.acceptRA; }
            // lib.optionalAttrs (w ? dhcp) { dhcp = w.dhcp; };
        }
      ) wan;

  evalFromInput =
    {
      tenantVlans,
      policyAccessTransitBase,
      corePolicyTransitVlan,
      ulaPrefix,
      tenantV4Base,

      policyAccessOffset ? 0,
      policyNodeName ? "s-router-policy-only",

      # Fabric host
      coreNodeName ? "s-router-core",

      accessNodePrefix ? "s-router-access",
      domain ? "lan.",
      reservedVlans ? [ 1 ],
      forbiddenVlanRanges ? [ ],
      defaultRouteMode ? "default",
      links ? { },
      wan ? null,

      # Optional explicit routing core node (context)
      coreRoutingNodeName ? null,
      ...
    }:

    let
      topoRaw = import ./topology-gen.nix { inherit lib; } {
        inherit
          tenantVlans
          policyAccessTransitBase
          corePolicyTransitVlan
          policyAccessOffset
          policyNodeName
          coreNodeName
          accessNodePrefix
          domain
          reservedVlans
          forbiddenVlanRanges
          ulaPrefix
          tenantV4Base
          ;
      };

      topoWithLinks = topoRaw // {
        inherit defaultRouteMode coreRoutingNodeName;
        links = (topoRaw.links or { }) // links // (mkWanLinks coreNodeName wan);
      };

      topoResolved = import ./topology-resolve.nix {
        inherit lib ulaPrefix tenantV4Base;
      } topoWithLinks;

      compiled = import ./compile/compile.nix {
        inherit lib;
        model = topoResolved;
      };
    in
    compiled;

in

args:
let
  topoInput = if args ? topology then args.topology else args;

  isResolved =
    topoInput ? nodes
    && topoInput ? links
    && topoInput ? ulaPrefix
    && topoInput ? tenantV4Base
    && !(topoInput ? tenantVlans);

in
if isResolved then
  import ./compile/compile.nix {
    inherit lib;
    model = topoInput;
  }
else
  evalFromInput topoInput

