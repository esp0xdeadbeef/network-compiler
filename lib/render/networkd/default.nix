{ lib }:

let
  utils = import ./utils.nix { inherit lib; };
  names = import ./names.nix { inherit lib; };
  routes = import ./routes.nix { inherit lib; };
  parentIf = import ./parent-if.nix { inherit lib; } { inherit utils; };

  mkUnits =
    import ./interface-units.nix
      {
        inherit lib;
      }
      {
        inherit names routes parentIf;
      };

  mkL2Units =
    {
      all,
      nodeName,
      linkName,
      iface,
    }:

    let
      carrier = iface.carrier or "lan";
      vlanId = iface.vlanId;

      parent = parentIf all nodeName carrier;

      vname = names.mkIfName {
        prefix = "v";
        hint = "${toString vlanId}-${linkName}";
        seed = "${nodeName}|${linkName}|${toString vlanId}";
      };

      bname = names.mkIfName {
        prefix = "br";
        hint = "-${linkName}";
        seed = "br|${nodeName}|${linkName}|${toString vlanId}";
      };
    in
    {
      netdevs = {
        "10-${vname}.netdev" = {
          netdevConfig = {
            Name = vname;
            Kind = "vlan";
          };
          vlanConfig.Id = vlanId;
        };

        "20-${bname}.netdev" = {
          netdevConfig = {
            Name = bname;
            Kind = "bridge";
          };
        };
      };

      networks = {
        "05-${parent}.network" = {
          matchConfig.Name = parent;
          networkConfig.VLAN = [ vname ];
        };

        "15-${vname}.network" = {
          matchConfig.Name = vname;
          networkConfig = {
            Bridge = bname;
            LinkLocalAddressing = "no";
          };
        };
      };
    };

in
{
  render =
    {
      all,
      nodeName,
      topologyRaw ? null,
    }:

    let
      allWithRaw =
        all
        // lib.optionalAttrs (topologyRaw != null) {
          topologyRaw = topologyRaw;
        };

      ifaces = allWithRaw.nodes.${nodeName}.interfaces or { };

      units = lib.mapAttrsToList (
        linkName: iface:
        let
          l2 = mkL2Units {
            inherit nodeName linkName iface;
            all = allWithRaw;
          };

          l3 = mkUnits {
            all = allWithRaw;
            inherit nodeName linkName iface;
          };
        in
        {
          netdevs = l2.netdevs // l3.netdevs;
          networks = l2.networks // l3.networks;
        }
      ) ifaces;

    in
    {
      netdevs = lib.foldl' (a: b: a // b.netdevs) { } units;
      networks = lib.foldl' (a: b: a // b.networks) { } units;
    };
}
