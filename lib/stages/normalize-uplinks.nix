{ lib }:

let
  recognizedNat44Modes = [
    "nat44"
    "masquerade"
    "snat"
  ];
  recognizedNat66Modes = [ "nat66" ];

  normalizeTranslatedPrefixes =
    t:
    lib.unique (
      builtins.filter (p: p != null && p != "") (
        (if builtins.isList (t.translatedPrefixes or null) then t.translatedPrefixes else [ ])
        ++ (
          if builtins.isList (t.translatedAddressOrPrefix or null) then t.translatedAddressOrPrefix else [ ]
        )
        ++ (if builtins.isList (t.translatedAddresses or null) then t.translatedAddresses else [ ])
        ++ [
          (t.translatedPrefix or "")
          (t.translatedAddress or "")
          (t.prefix or "")
          (t.address or "")
        ]
      )
    );

  normalizeTranslation =
    uplinkName: family: t:
    if t == null then
      { }
    else if !builtins.isAttrs t then
      throw "intent topology uplink '${uplinkName}' egress.${family}.translation must be an attribute set"
    else
      let
        mode = t.mode or null;
        recognized = if family == "ipv4" then recognizedNat44Modes else recognizedNat66Modes;
      in
      if mode != null && !(builtins.elem mode recognized) then
        throw "intent topology uplink '${uplinkName}' egress.${family}.translation.mode '${builtins.toString mode}' is not recognized; expected one of ${builtins.concatStringsSep ", " recognized}"
      else
        t
        // {
          translatedPrefixes = normalizeTranslatedPrefixes t;
        };

  normalizeEgress =
    uplinkName: e:
    if e == null then
      { }
    else if !builtins.isAttrs e then
      throw "intent topology uplink '${uplinkName}' egress must be an attribute set"
    else if e ? mode || e ? bgp then

      builtins.throw (
        builtins.toJSON {
          code = "E_SUPERSEDED_CONTRACT";
          site = null;
          path = [
            "topology"
            "nodes"
          ];
          message = "uplink egress declares a per-uplink routing/egress mode (not caught by FS-081 pre-check)";
          spec = "FS-081 Superseded-Contract Rejection; owning item: FS-481 Routing Behavior Selection";
          hints = [ "Remove 'egress.mode' and 'egress.bgp'; declare routing behaviors on the selection." ];
        }
      )
    else
      e
      // {
        ipv4 =
          if builtins.isAttrs (e.ipv4 or null) then
            e.ipv4 // { translation = normalizeTranslation uplinkName "ipv4" (e.ipv4.translation or null); }
          else
            { };
        ipv6 =
          if builtins.isAttrs (e.ipv6 or null) then
            e.ipv6 // { translation = normalizeTranslation uplinkName "ipv6" (e.ipv6.translation or null); }
          else
            { };
      };

  normalizeUplink =
    uplinkName: v:
    let
      ipv4 = v.ipv4 or [ ];
      ipv6 = v.ipv6 or [ ];

      defaultV4 = "0.0.0.0/0";
      defaultV6 = "::/0";
      nonDefaultV4 = builtins.filter (p: p != defaultV4) ipv4;
      nonDefaultV6 = builtins.filter (p: p != defaultV6) ipv6;
      tenantPrefixList = (builtins.length nonDefaultV4 > 1) || (builtins.length nonDefaultV6 > 1);
    in
    if tenantPrefixList then
      throw (
        "FS-260-HDS-010-SDS-010-SMS-010: uplink '"
        + uplinkName
        + "' carries a tenant-prefix list ("
        + builtins.toString (builtins.length nonDefaultV4)
        + " IPv4, "
        + builtins.toString (builtins.length nonDefaultV6)
        + " IPv6 non-default prefixes). An uplink is a provider/WAN egress surface with one provider prefix or the default route. Express tenant and peer-site reachability as a relation (source scope to a named egress surface), not as an uplink prefix list."
      )
    else
      v
      // {
        name = uplinkName;
        inherit ipv4 ipv6;
        ingressSubject = v.ingressSubject or null;
        egress = normalizeEgress uplinkName (v.egress or null);
      };

  forNodeList =
    siteKey: nodeName: u:
    if u == null then
      [ ]
    else if builtins.isAttrs u then
      let
        names = lib.sort builtins.lessThan (builtins.attrNames u);
      in
      map (name: normalizeUplink name u.${name}) names
    else
      [ ];

  forNodeAttrs =
    siteKey: nodeName: u:
    if u == null then
      { }
    else if builtins.isAttrs u then
      lib.listToAttrs (
        map (name: {
          inherit name;
          value = normalizeUplink name u.${name};
        }) (lib.sort builtins.lessThan (builtins.attrNames u))
      )
    else
      { };
in
{
  inherit forNodeList forNodeAttrs normalizeUplink;
}
