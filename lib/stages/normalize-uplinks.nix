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
    v
    // {
      name = uplinkName;
      ipv4 = v.ipv4 or [ ];
      ipv6 = v.ipv6 or [ ];
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
