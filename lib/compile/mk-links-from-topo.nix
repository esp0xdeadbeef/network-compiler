{ lib }:

nodeName: topo:

let
  node = topo.nodes.${nodeName} or (throw "topology: missing node '${nodeName}'");
  nodeIfs = node.ifs or (throw "topology: node '${nodeName}' missing ifs");
  links = topo.links or { };

  shortHash = s: builtins.substring 0 4 (builtins.hashString "sha256" s);

  kernelBridgeName =
    l:
    let
      base =
        if (l.kind or "") == "p2p" then
          "br-ce"
        else if (l.kind or "") == "l2" then
          "br-lg"
        else
          "br-x";
      ident =
        if l ? name then l.name else (throw "link missing semantic 'name' (topology.links.<x>.name)");
      h = shortHash ident;
    in
    "${base}-${h}";

  linkNamesForNode = lib.filter (
    lname:
    let
      l = links.${lname};
    in
    lib.elem nodeName (l.members or [ ])
  ) (lib.attrNames links);

  carrierIf =
    l:
    let
      c = l.carrier or (throw "link missing carrier");
    in
    nodeIfs.${c} or (throw "node '${nodeName}' missing carrier if '${c}'");

  vlanIdStr = l: toString (l.vlanId or (throw "link missing vlanId"));
  vlanIfName = l: "${carrierIf l}.${vlanIdStr l}";

  mkVlanNetdev = l: {
    netdevConfig = {
      Name = vlanIfName l;
      Kind = "vlan";
    };
    vlanConfig.Id = lib.toInt (vlanIdStr l);
  };

  mkBridgeNetdev = l: {
    netdevConfig = {
      Name = kernelBridgeName l;
      Kind = "bridge";
    };
  };

  mkPortNetwork = l: {
    matchConfig.Name = vlanIfName l;
    networkConfig = {
      DHCP = "no";
      Bridge = kernelBridgeName l;
      ConfigureWithoutCarrier = true;
    };
  };

  mkCarrierNetwork = carrier: vlanIfs: {
    matchConfig.Name = carrier;
    networkConfig = {
      DHCP = "no";
      VLAN = vlanIfs;
    };
  };

  carriersUsed = lib.unique (map (lname: carrierIf links.${lname}) linkNamesForNode);

  vlanIfsForCarrier =
    carrier:
    map (lname: vlanIfName links.${lname}) (
      lib.filter (lname: carrierIf links.${lname} == carrier) linkNamesForNode
    );

in
{
  systemd.network.netdevs =
    (lib.listToAttrs (
      map (lname: {
        name = "10-vlan-${lname}";
        value = mkVlanNetdev links.${lname};
      }) linkNamesForNode
    ))
    // (lib.listToAttrs (
      map (lname: {
        name = "20-bridge-${lname}";
        value = mkBridgeNetdev links.${lname};
      }) linkNamesForNode
    ));

  systemd.network.networks =

    (lib.listToAttrs (
      map (carrier: {
        name = "10-carrier-${carrier}";
        value = mkCarrierNetwork carrier (vlanIfsForCarrier carrier);
      }) carriersUsed
    ))
    //

      (lib.listToAttrs (
        map (lname: {
          name = "15-port-${lname}";
          value = mkPortNetwork links.${lname};
        }) linkNamesForNode
      ));
}
