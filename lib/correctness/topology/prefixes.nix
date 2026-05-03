{ lib }:

let
  util = import ../util.nix { inherit lib; };
  inherit (util) ensure;

  parseIpv4Cidr =
    siteKey: path: cidr:
    let
      parts = lib.splitString "/" cidr;

      _len = ensure (builtins.length parts == 2) {
        code = "E_UPLINK_INVALID_CIDR";
        site = siteKey;
        inherit path;
        message = "invalid IPv4 CIDR '${toString cidr}'";
        hints = [ "Use a.b.c.d/prefix." ];
      };

      base = builtins.elemAt parts 0;
      prefix = lib.toInt (builtins.elemAt parts 1);
      octets = lib.splitString "." base;

      _octLen = ensure (builtins.length octets == 4) {
        code = "E_UPLINK_INVALID_IPV4";
        site = siteKey;
        inherit path;
        message = "invalid IPv4 address '${base}'";
        hints = [ "Use four octets a.b.c.d." ];
      };

      toOctet =
        s:
        let
          v = lib.toInt s;
        in
        ensure (0 <= v && v <= 255) {
          code = "E_UPLINK_INVALID_IPV4";
          site = siteKey;
          inherit path;
          message = "IPv4 octet out of range in '${base}'";
          hints = [ "Each octet must be 0..255." ];
        };

      _ = toOctet (builtins.elemAt octets 0);
      _1 = toOctet (builtins.elemAt octets 1);
      _2 = toOctet (builtins.elemAt octets 2);
      _3 = toOctet (builtins.elemAt octets 3);

      _pref = ensure (0 <= prefix && prefix <= 32) {
        code = "E_UPLINK_INVALID_PREFIX";
        site = siteKey;
        inherit path;
        message = "invalid IPv4 prefix in '${cidr}'";
        hints = [ "Use /0..../32." ];
      };
    in
    true;

  parseIpv6Cidr =
    siteKey: path: cidr:
    let
      _parsed = lib.network.ipv6.fromString cidr;
    in
    true;

  validateOnePrefix =
    siteKey: path: cidr:
    if lib.hasInfix ":" cidr then parseIpv6Cidr siteKey path cidr else parseIpv4Cidr siteKey path cidr;

  validateIngressSubject =
    siteKey: path: ingressSubject:
    if ingressSubject == null then
      true
    else
      let
        _shape = ensure (builtins.isAttrs ingressSubject) {
          code = "E_UPLINK_INGRESS_SUBJECT_SHAPE";
          site = siteKey;
          inherit path;
          message = "uplink.ingressSubject must be an attrset or null";
          hints = [ "Use ingressSubject = { kind = \"tenant\"; name = \"...\"; }." ];
        };

        kind = ingressSubject.kind or null;
        name = ingressSubject.name or null;

        _kind = ensure (kind != null) {
          code = "E_UPLINK_INGRESS_SUBJECT_KIND";
          site = siteKey;
          path = path ++ [ "kind" ];
          message = "uplink.ingressSubject.kind is required";
          hints = [ "Set kind = \"tenant\"." ];
        };

        _name = ensure (name != null && builtins.isString name && name != "") {
          code = "E_UPLINK_INGRESS_SUBJECT_NAME";
          site = siteKey;
          path = path ++ [ "name" ];
          message = "uplink.ingressSubject.name is required";
          hints = [ "Set name = \"...\"." ];
        };
      in
      true;
in
{
  inherit validateOnePrefix validateIngressSubject;
}
