{ lib }:

let
  util = import ../util.nix { inherit lib; };
  inherit (util) ensure assertUnique throwError;

  normalizeExternalSelector =
    siteKey: path: overlayNames: uplinkNames: ext:
    let
      hasName = ext ? name;
      hasUplinks = ext ? uplinks;

      _oneSelector = ensure (hasName || hasUplinks) {
        code = "E_CONTRACT_EXTERNAL_SELECTOR";
        site = siteKey;
        path = path;
        message = "external selector requires either name or uplinks";
        hints = [
          "Use name = \"east-west\" for overlays."
          "Or use uplinks = [ \"wan\" ] for explicit uplink selection."
        ];
      };

      _notBoth = ensure (!(hasName && hasUplinks)) {
        code = "E_CONTRACT_EXTERNAL_SELECTOR";
        site = siteKey;
        path = path;
        message = "external selector must use either name or uplinks, not both";
        hints = [
          "Keep name only for overlays or the single-uplink alias 'wan'."
          "Use uplinks = [ \"<uplink-name>\" ] for explicit uplink selection."
        ];
      };
    in
    if hasUplinks then
      let
        uplinks0 = ext.uplinks;

        _shape =
          ensure (builtins.isList uplinks0 && uplinks0 != [ ] && builtins.all builtins.isString uplinks0)
            {
              code = "E_CONTRACT_EXTERNAL_UPLINKS";
              site = siteKey;
              path = path ++ [ "uplinks" ];
              message = "external.uplinks must be a non-empty list of uplink names";
              hints = [ "Use uplinks = [ \"wan\" ] or uplinks = [ \"isp-a\" \"isp-b\" ]." ];
            };

        _uniq = assertUnique "external uplink selector" uplinks0;

        _exists = ensure (builtins.all (u: builtins.elem u uplinkNames) uplinks0) {
          code = "E_CONTRACT_UNKNOWN_EXTERNAL";
          site = siteKey;
          path = path ++ [ "uplinks" ];
          message = "relation references unknown uplink";
          hints = [ "Declare the uplink under topology.nodes.<core>.uplinks.<name>." ];
        };
      in
      {
        kind = "external";
        uplinks = lib.sort builtins.lessThan uplinks0;
      }
    else
      let
        name = ext.name or null;

        _name = ensure (name != null && builtins.isString name && name != "") {
          code = "E_CONTRACT_SUBJECT_NAME";
          site = siteKey;
          path = path ++ [ "name" ];
          message = "external subject requires a non-empty name";
          hints = [ "Set name = \"wan\" for the single-uplink alias or name = \"east-west\" for overlays." ];
        };
      in
      if builtins.elem name overlayNames then
        {
          kind = "external";
          inherit name;
        }
      else if builtins.elem name uplinkNames then
        if name == "wan" then
          {
            kind = "external";
            inherit name;
          }
        else
          throwError {
            code = "E_UPLINK_LEGACY_SELECTOR";
            site = siteKey;
            path = path ++ [ "name" ];
            message = "uplink '${name}' must be selected via external.uplinks";
            hints = [
              "Replace name = \"${name}\" with uplinks = [ \"${name}\" ]."
              "Keep external.name only for overlay names and the single-uplink alias 'wan'."
            ];
          }
      else
        throwError {
          code = "E_CONTRACT_UNKNOWN_EXTERNAL";
          site = siteKey;
          path = path ++ [ "name" ];
          message = "relation references unknown external '${name}'";
          hints = [
            "Declare an uplink under topology.nodes.<core>.uplinks.<name>."
            "Or declare a transport overlay with transport.overlays[].name."
          ];
        };
in
{
  inherit normalizeExternalSelector;
}
