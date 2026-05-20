{ lib }:

let
  util = import ../util.nix { inherit lib; };
  inherit (util) assertUnique throwError;

  normalizeMatch =
    idx: trafficTypeName: m:
    let
      proto =
        if builtins.isAttrs m && m ? proto then
          m.proto
        else if builtins.isAttrs m && m ? l4 then
          m.l4
        else
          "any";

      family =
        if builtins.isAttrs m && m ? family then
          m.family
        else if builtins.isAttrs m && m ? families then
          let
            fs = m.families;
          in
          if fs == [ ] then "any" else builtins.elemAt fs 0
        else
          "any";

      dports = if builtins.isAttrs m && m ? dports then m.dports else [ ];
    in
    {
      inherit proto family dports;
    };

  buildTrafficTypeIndex =
    communicationContract:
    let
      trafficTypes = communicationContract.trafficTypes or [ ];

      _uniqTrafficTypes = assertUnique "traffic type name" (map (t: t.name) trafficTypes);

      normalizeOne = t: {
        name = t.name;
        match = lib.imap0 (idx: m: normalizeMatch idx t.name m) (t.match or [ ]);
      };
    in
    builtins.listToAttrs (
      map
        (t: {
          name = t.name;
          value = normalizeOne t;
        })
        trafficTypes
    );

  trafficTypeDef =
    siteKey: idx: trafficTypeIndex: trafficTypeName:
    if trafficTypeName == "any" then
      {
        name = "any";
        match = [
          {
            proto = "any";
            family = "any";
            dports = [ ];
          }
        ];
      }
    else if builtins.hasAttr trafficTypeName trafficTypeIndex then
      trafficTypeIndex.${trafficTypeName}
    else
      throwError {
        code = "E_CONTRACT_UNKNOWN_TRAFFIC_TYPE";
        site = siteKey;
        path = [
          "communicationContract"
          "relations"
          idx
          "trafficType"
        ];
        message = "relation references unknown trafficType '${trafficTypeName}'";
        hints = [ "Declare trafficTypes = [ { name = \"${trafficTypeName}\"; match = ...; } ]." ];
      };

  buildServiceIndex =
    communicationContract:
    let
      services = communicationContract.services or [ ];
      _uniqServices = assertUnique "service name" (map (s: s.name) services);
    in
    builtins.listToAttrs (
      map
        (s: {
          name = s.name;
          value = s;
        })
        services
    );
in
{
  inherit
    buildTrafficTypeIndex
    trafficTypeDef
    buildServiceIndex
    ;
}
