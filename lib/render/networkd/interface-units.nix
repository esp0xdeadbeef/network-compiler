# ./lib/render/networkd/interface-units.nix
# ./lib/render/networkd/interface-units.nix
{ lib }:

{
  names,
  routes,
  parentIf,
}:

{
  all,
  nodeName,
  linkName,
  iface,
}:

let
  needsBridge = iface.kind == "lan";
  isWan = (iface.kind or null) == "wan";

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

  networkOn = if needsBridge then bname else vname;

  routeSections = map routes.mkRouteSection ((iface.routes4 or [ ]) ++ (iface.routes6 or [ ]));

  dhcp = iface.dhcp or false;
  acceptRA = iface.acceptRA or false;

  dhcpMode =
    if isWan && dhcp then
      "yes"
    else
      "no";

  raMode =
    if isWan && acceptRA then
      "yes"
    else
      "no";

in
{
  netdevs = {
    "20-${vname}.netdev" = {
      netdevConfig = {
        Name = vname;
        Kind = "vlan";
      };
      vlanConfig.Id = vlanId;
    };
  }
  // lib.optionalAttrs needsBridge {
    "20-${bname}.netdev" = {
      netdevConfig = {
        Name = bname;
        Kind = "bridge";
      };
    };
  };

  networks = {
    "10-${parent}.network" = {
      matchConfig.Name = parent;
      networkConfig.VLAN = vname;
    };

    "30-${networkOn}.network" = {
      matchConfig.Name = networkOn;
      networkConfig = {
        Address = lib.filter (x: x != null) [
          (iface.addr4 or null)
          (iface.addr6 or null)
        ];
        IPForward = "yes";

        # Dynamic WAN support
        DHCP = dhcpMode;
        IPv6AcceptRA = raMode;
      };
      routes = routeSections;
    };
  }
  // lib.optionalAttrs needsBridge {
    "25-${vname}.network" = {
      matchConfig.Name = vname;
      networkConfig = {
        Bridge = bname;
        LinkLocalAddressing = "no";
      };
    };
  };
}

