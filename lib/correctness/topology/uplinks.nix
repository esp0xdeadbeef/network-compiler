{ lib }:

let
  util = import ../util.nix { inherit lib; };
  prefixes = import ./prefixes.nix { inherit lib; };
  inherit (util) ensure assertUnique;
  inherit (prefixes) validateOnePrefix validateIngressSubject;

  validateUplinkPrefixes =
    siteKey: path: uplink:
    let
      ipv4 = uplink.ipv4 or [ ];
      ipv6 = uplink.ipv6 or [ ];
      ingressSubject = uplink.ingressSubject or null;

      _v4shape = ensure (builtins.isList ipv4 && builtins.all builtins.isString ipv4) {
        code = "E_UPLINK_PREFIX_SHAPE";
        site = siteKey;
        path = path ++ [ "ipv4" ];
        message = "uplink.ipv4 must be a list of CIDR strings";
        hints = [ "Use ipv4 = [ \"0.0.0.0/0\" \"203.0.113.0/24\" ]." ];
      };

      _v6shape = ensure (builtins.isList ipv6 && builtins.all builtins.isString ipv6) {
        code = "E_UPLINK_PREFIX_SHAPE";
        site = siteKey;
        path = path ++ [ "ipv6" ];
        message = "uplink.ipv6 must be a list of CIDR strings";
        hints = [ "Use ipv6 = [ \"::/0\" \"2001:db8::/32\" ]." ];
      };

      _nonEmpty = ensure (ipv4 != [ ] || ipv6 != [ ]) {
        code = "E_UPLINK_PREFIX_EMPTY";
        site = siteKey;
        inherit path;
        message = "uplink must include at least one ipv4 and/or ipv6 prefix";
        hints = [ "Set ipv4 and/or ipv6 to a non-empty list of CIDR prefixes." ];
      };

      _v4ok = builtins.foldl' (acc: p: acc && validateOnePrefix siteKey (path ++ [ "ipv4" ]) p) true ipv4;
      _v6ok = builtins.foldl' (acc: p: acc && validateOnePrefix siteKey (path ++ [ "ipv6" ]) p) true ipv6;
      _ingressSubjectOk = validateIngressSubject siteKey (path ++ [ "ingressSubject" ]) ingressSubject;

      _forced = builtins.deepSeq
        {
          inherit
            _v4shape
            _v6shape
            _nonEmpty
            _v4ok
            _v6ok
            _ingressSubjectOk
            ;
        }
        true;
    in
    if _forced then true else true;

  normalizeUplinks =
    siteKey: nodeName: u:
    if u == null then
      [ ]
    else if builtins.isAttrs u then
      let
        names = lib.sort builtins.lessThan (builtins.attrNames u);

        _uniq = assertUnique "uplink name" names;

        uplinks = map
          (
            name:
            let
              v = u.${name};

              _shape = ensure (builtins.isAttrs v) {
                code = "E_UPLINK_ENTRY_SHAPE";
                site = siteKey;
                path = [
                  "topology"
                  "nodes"
                  nodeName
                  "uplinks"
                  name
                ];
                message = "uplink '${name}' must be an attrset";
                hints = [ "Use uplinks.${name} = { ipv4 = [\"...\"]; ipv6 = [\"...\"]; }." ];
              };

              _valid = validateUplinkPrefixes siteKey [
                "topology"
                "nodes"
                nodeName
                "uplinks"
                name
              ]
                v;
            in
            v
            // {
              inherit name;
              ipv4 = v.ipv4 or [ ];
              ipv6 = v.ipv6 or [ ];
              ingressSubject = v.ingressSubject or null;
            }
          )
          names;
      in
      if _uniq then uplinks else uplinks
    else
      [ ];
in
{
  inherit normalizeUplinks;
}
