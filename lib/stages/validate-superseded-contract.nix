{ lib }:

let
  util = import ../correctness/util.nix { inherit lib; };
  inherit (util) throwError;

  fail =
    {
      site,
      path,
      owner,
      message,
      hints,
    }:
    throwError {
      code = "E_SUPERSEDED_CONTRACT";
      inherit
        site
        path
        message
        hints
        ;
      spec = "FS-081 Superseded-Contract Rejection; owning item: ${owner}";
    };

  nodesOf =
    site:
    let
      topo = if builtins.isAttrs (site.topology or null) then site.topology else { };
    in
    if builtins.isAttrs (topo.nodes or null) then topo.nodes else { };

  checkUplinkReachability =
    siteKey: nodeName: uplinkName: uplink:
    let
      ipv4 = if builtins.isList (uplink.ipv4 or null) then uplink.ipv4 else [ ];
      ipv6 = if builtins.isList (uplink.ipv6 or null) then uplink.ipv6 else [ ];
      nonDefault = builtins.filter (p: p != "0.0.0.0/0" && p != "::/0") (ipv4 ++ ipv6);
      hasDefault = builtins.elem "0.0.0.0/0" ipv4 || builtins.elem "::/0" ipv6;
    in
    if !hasDefault && builtins.length nonDefault > 1 then
      fail {
        site = siteKey;
        path = [
          "topology"
          "nodes"
          nodeName
          "uplinks"
          uplinkName
        ];
        owner = "FS-260-HDS-010-SDS-010-SMS-010 Default Site Fabric Chain";
        message = "uplink '${uplinkName}' on node '${nodeName}' carries a tenant-prefix list (${builtins.toString (builtins.length nonDefault)} non-default prefixes); an uplink is a provider/WAN/exit surface (one provider prefix or the default) or a service/fabric uplink, not a tenant or peer-site reachability list";
        hints = [
          "Declare tenant and peer-site reachability with 'offers'/'selects' on the scopes (FS-322), not as an uplink prefix list."
          "A core or access that federates other scopes over fabric links declares no uplinks."
        ];
      }
    else
      true;

  checkUplink =
    siteKey: nodeName: uplinkName: uplink:
    let
      egress = if builtins.isAttrs (uplink.egress or null) then uplink.egress else { };
    in
    if egress ? mode || egress ? bgp then
      fail {
        site = siteKey;
        path = [
          "topology"
          "nodes"
          nodeName
          "uplinks"
          uplinkName
          "egress"
        ];
        owner = "FS-481 Routing Behavior Selection";
        message = "uplink '${uplinkName}' on node '${nodeName}' declares a per-uplink routing/egress mode";
        hints = [
          "Remove 'egress.mode' and 'egress.bgp'."
          "Declare optional routing behaviors on the selecting scope's selection ('behaviors')."
        ];
      }
    else
      checkUplinkReachability siteKey nodeName uplinkName uplink;

  checkNode =
    siteKey: nodeName: node:
    let
      uplinks = if builtins.isAttrs (node.uplinks or null) then node.uplinks else { };
    in
    lib.all (u: checkUplink siteKey nodeName u uplinks.${u}) (builtins.attrNames uplinks);

  removedTopLevelKeys = {
    policy = "communicationContract";
    internetMode = "exit reachability (scope 'offers'/'selects')";
    routingStyle = "routing behaviors on the selection";
    providerProfile = "an exit scope";
  };

  checkTopLevel =
    siteKey: site:
    lib.all (
      key:
      if site ? ${key} then
        fail {
          site = siteKey;
          path = [ key ];
          owner = "FS-081 Superseded-Contract Rejection";
          message = "top-level intent key '${key}' is removed";
          hints = [ "Use ${removedTopLevelKeys.${key}} instead." ];
        }
      else
        true
    ) (builtins.attrNames removedTopLevelKeys);

  perSite =
    siteKey: site:
    let
      nodes = nodesOf site;
    in
    {
      _topLevel = checkTopLevel siteKey site;
      _nodes = lib.all (n: checkNode siteKey n nodes.${n}) (builtins.attrNames nodes);
    };
in
{
  inherit perSite;
}
